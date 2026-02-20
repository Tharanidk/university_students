import ballerina/data.csv;
import ballerina/email;
import ballerina/ftp;
import ballerina/log;
import ballerina/sql;
import ballerina/time;
import ballerina/io;
import ballerina/lang.regexp as regexp;

// Download file from SFTP
function downloadFile(string filePath) returns byte[]|error {
    ftp:Client sftpClient = check getSftpClient();
    log:printInfo(string `Downloading: ${filePath}`);

    string content = check sftpClient->getText(filePath);
    byte[] fileContent = content.toBytes();

    log:printInfo(string `Downloaded ${fileContent.length()} bytes`);
    return fileContent;

}

// Validate email domain
function validateEmail(string email) returns error? {
    if !email.endsWith("@epfl.ch") {
        return error(string `Invalid email domain: ${email}. Must end with @epfl.ch`);
    }
}

// Parse and validate CSV 
function parseAndValidateCsv(byte[] blobContent) returns Student[]|error {
    byte[] content = blobContent;
    if blobContent.length() >= 3 && blobContent[0] == 0xEF && blobContent[1] == 0xBB && blobContent[2] == 0xBF {
        log:printInfo("BOM detected — stripping");
        content = blobContent.slice(3);
    }

    string csvString = check string:fromBytes(content);
    log:printInfo("Encoding validation passed: valid UTF-8");

    StudentCsv[] csvRecords = check csv:parseString(csvString);
    log:printInfo(string `Schema validation passed: ${csvRecords.length()} records`);

    return from StudentCsv r in csvRecords
        select {
            id: r.id,
            last_name: r.nom,
            first_name: r.prenom,
            email: r.email,
            active: r.actif.equalsIgnoreCaseAscii("true") || r.actif == "1"
        };
}

function processStudents(Student[] students) returns UpsertResult|error {
    int insertions = 0;
    int updates = 0;
    int deactivations = 0;
    int errors = 0;

    foreach Student s in students {
        do {
            check validateEmail(s.email);

            stream<record {|int id;|}, sql:Error?> rs = mysqlClient->query(
                `SELECT id FROM students WHERE id = ${s.id}`
            );
            record {|int id;|}[] rows = check from var r in rs
                select r;

            if rows.length() == 0 {
                int active = s.active ? 1 : 0;
                _ = check mysqlClient->execute(
                    `INSERT INTO students (id, last_name, first_name, email, active)
                     VALUES (${s.id}, ${s.last_name}, ${s.first_name}, ${s.email}, ${active})`
                );
                insertions += 1;
            } else if s.active {
                _ = check mysqlClient->execute(
                    `UPDATE students SET last_name = ${s.last_name}, first_name = ${s.first_name},
                         email = ${s.email}, active = 1 WHERE id = ${s.id}`
                );
                updates += 1;
            } else {
                _ = check mysqlClient->execute(
                    `UPDATE students SET active = 0 WHERE id = ${s.id}`
                );
                deactivations += 1;
            }
        } on fail error e {
            errors += 1;
            log:printError(string `ERROR: Student ${s.id} — ${e.message()}`);
        }
    }

    log:printInfo(string `Result: ${insertions} created, ${updates} updated, ${deactivations} deactivated, ${errors} errors`);
    return {insertions, updates, deactivations, errors};
}

// Process files
function processFile(byte[] csvBytes, string startTime) returns error? {
    Student[] students = check parseAndValidateCsv(csvBytes);
    UpsertResult result = check processStudents(students);
    string endTime = getCurrentTime();

    ProcessingReport report = {
        totalCsvRows: students.length(),
        validRows: result.insertions + result.updates + result.deactivations,
        invalidRows: result.errors,
        insertions: result.insertions,
        updates: result.updates,
        deactivations: result.deactivations,
        errors: result.errors,
        startTime: startTime,
        endTime: endTime
    };

    string reportText = generateReport(report);
    check sendEmailNotification(reportText);
}

type BirthDateUpdateStats record {|
    int updated;
    int skipped;
    int errors;
|};

function processBirthDateFile(byte[] csvBytes) returns error? {
    check ensureDateOfBirthColumn();

    csvRecordDN[] recordsDN = check parseBirthDateCsv(csvBytes);
    csvRecord[] studentCsvRecords = check loadStudentCsvRecords();
    csvRecordDN[] joinedRecords = joinCsvRecordAndCsvRecordDN(studentCsvRecords, recordsDN);
    log:printInfo(string `Joined ${joinedRecords.length()} records by id`);

    int unmatchedCount = recordsDN.length() - joinedRecords.length();
    BirthDateUpdateStats stats = check applyBirthDateUpdates(joinedRecords, unmatchedCount);
    log:printInfo(string `Birth dates: ${stats.updated} updated, ${stats.skipped} skipped, ${stats.errors} errors`);
}

function ensureDateOfBirthColumn() returns error? {
    do {
        _ = check mysqlClient->execute(
            `ALTER TABLE students ADD COLUMN date_of_birth DATE AFTER email`
        );
        log:printInfo("Added date_of_birth column");
    } on fail error e {
        if e.message().toLowerAscii().includes("duplicate") {
            log:printInfo("date_of_birth column already exists");
        } else {
            return e;
        }
    }
}

function parseBirthDateCsv(byte[] csvBytes) returns csvRecordDN[]|error {
    byte[] content = csvBytes;
    if csvBytes.length() >= 3 && csvBytes[0] == 0xEF && csvBytes[1] == 0xBB && csvBytes[2] == 0xBF {
        content = csvBytes.slice(3);
    }

    string csvString = check string:fromBytes(content);
    csvRecordDN[] recordsDN = check csv:parseString(csvString, {delimiter: ";"});
    log:printInfo(string `Parsed ${recordsDN.length()} birth date records`);
    return recordsDN;
}

function loadStudentCsvRecords() returns csvRecord[]|error {
    stream<record {|int id; string last_name; string first_name; string email; int active;|}, sql:Error?> studentRs =
        mysqlClient->query(`SELECT id, last_name, first_name, email, active FROM students`);

    return check from var row in studentRs
        select {
            id: row.id,
            nom: row.last_name,
            prenom: row.first_name,
            email: row.email,
            actif: row.active == 1 ? "1" : "0"
        };
}

function applyBirthDateUpdates(csvRecordDN[] joinedRecords, int unmatchedCount) returns BirthDateUpdateStats|error {
    BirthDateUpdateStats stats = {
        updated: 0,
        skipped: unmatchedCount,
        errors: 0
    };

    foreach csvRecordDN rec in joinedRecords {
        do {
            string dateStr = rec.datenaissance.trim();
            if dateStr.length() == 0 {
                stats.skipped += 1;
                log:printWarn(string `Student ${rec.id}: No birth date — skipping`);
                continue;
            }

            string formattedDate = check convertDateFormat(dateStr);
            sql:ExecutionResult result = check mysqlClient->execute(
                `UPDATE students SET date_of_birth = ${formattedDate} WHERE id = ${rec.id}`
            );

            int affected = result.affectedRowCount ?: 0;
            if affected > 0 {
                stats.updated += 1;
                log:printInfo(string `Birth date updated: ${rec.id} -> ${formattedDate}`);
            } else {
                stats.skipped += 1;
                log:printWarn(string `Student ${rec.id} not found in database`);
            }
        } on fail error e {
            stats.errors += 1;
            log:printError(string `Error: Student ${rec.id} — ${e.message()}`);
        }
    }

    return stats;
}

// In-memory inner join of student and birth-date CSV rows by `id`.
function joinCsvRecordAndCsvRecordDN(csvRecord[] csvRecords, csvRecordDN[] csvRecordsDN) returns csvRecordDN[] {
    map<csvRecord> recordsById = {};
    foreach csvRecord rec in csvRecords {
        recordsById[rec.id.toString()] = rec;
    }

    csvRecordDN[] joined = [];
    foreach csvRecordDN recDN in csvRecordsDN {
        csvRecord? rec = recordsById[recDN.id.toString()];
        if rec is csvRecord {
            joined.push({
                id: recDN.id,
                nom: rec.nom,
                prenom: rec.prenom,
                email: rec.email,
                datenaissance: recDN.datenaissance,
                actif: rec.actif
            });
        }
    }
    return joined;
}

function convertDateFormat(string dateStr) returns string|error {
    string[] parts = [];
    if dateStr.includes("/") {
        parts = re `/`.split(dateStr);
    } else if dateStr.includes(".") {
        parts = re `\.`.split(dateStr);
    } else {
        return error(string `Unknown date format: ${dateStr}`);
    }
    if parts.length() != 3 {
        return error(string `Invalid date: ${dateStr}`);
    }
    string day = parts[0].trim();
    string month = parts[1].trim();
    string year = parts[2].trim();
    if day.length() == 1 {
        day = string `0${day}`;
    }
    if month.length() == 1 {
        month = string `0${month}`;
    }
    int|error m = int:fromString(month);
    int|error d = int:fromString(day);
    if m is int && (m < 1 || m > 12) {
        return error(string `Invalid month ${month} in date: ${dateStr}`);
    }
    if d is int && (d < 1 || d > 31) {
        return error(string `Invalid day ${day} in date: ${dateStr}`);
    }
    return string `${year}-${month}-${day}`;
}

// Generate report
function generateReport(ProcessingReport r) returns string {
    return string `
====================================================
     STUDENT DATA SYNC - PROCESSING REPORT
====================================================
  Start Time    : ${r.startTime}
  End Time      : ${r.endTime}
----------------------------------------------------
  CSV PROCESSING
  Total CSV Rows : ${r.totalCsvRows}
  Valid Rows     : ${r.validRows}
  Invalid Rows   : ${r.invalidRows}
----------------------------------------------------
  DATABASE OPERATIONS
  Insertions     : ${r.insertions}
  Updates        : ${r.updates}
  Deactivations  : ${r.deactivations}
  Errors         : ${r.errors}
----------------------------------------------------
  Status: ${r.errors == 0 ? "SUCCESS" : "COMPLETED WITH ERRORS"}
====================================================`;
}

function sendEmailNotification(string report) returns error? {
    if !enableEmail {
        log:printInfo("Email notifications disabled");
        return;
    }

    email:SmtpClient smtp = check new (
        host = smtpHost, username = smtpUser, password = smtpPassword,
        clientConfig = {port: smtpPort, security: email:SSL}
    );

    check smtp->sendMessage({
        to: recipientEmail,
        subject: "EPFL Student Sync - Processing Report",
        'from: smtpUser,
        body: report
    });
    log:printInfo(string `Email sent to ${recipientEmail}`);
}

function getCurrentTime() returns string {
    return time:utcToString(time:utcNow());
}

// Function to archive processed file
function archiveFile(string originalFilePath) returns error? {
    log:printInfo(string `Archiving file: ${originalFilePath}`);
    ftp:Client sftpClient = check getSftpClient();
    // Extract file name from path
    regexp:RegExp pathRegex = check regexp:fromString("/");
    string[] pathParts = pathRegex.split(originalFilePath);
    string fileName = pathParts[pathParts.length() - 1];

    // Construct archived file path
    string timestamp = re `T`.replaceAll(
        time:utcToString(time:utcNow()).substring(0, 19), "_"
    );
    timestamp = re `:`.replaceAll(timestamp, "-");
    
    // Extract name and extension
    int? dotIndex = fileName.lastIndexOf(".");
    string nameWithoutExt = dotIndex is int ? fileName.substring(0, dotIndex) : fileName;
    string ext = dotIndex is int ? fileName.substring(dotIndex) : "";
    
    string archivedFileName = string `${nameWithoutExt}_${timestamp}${ext}`;

    // Build archive directory from original path (sibling "Archived" folder)
    string[] originalParts = pathRegex.split(originalFilePath);
    string archiveDir = "";
    foreach int i in 0 ..< originalParts.length() - 1 {
        if originalParts[i].length() > 0 {
            archiveDir = archiveDir + "/" + originalParts[i];
        }
    }
    archiveDir = archiveDir + "/Archived";

    string archivedPath = archiveDir + "/" + archivedFileName;

    // Get original file content
    stream<byte[] & readonly, io:Error?> fileStream = check sftpClient->get(originalFilePath);

    // Convert stream to byte array for putting to new location
    byte[] fileContent = [];
    check fileStream.forEach(function(byte[] & readonly chunk) {
        foreach byte b in chunk {
            fileContent.push(b);
        }
    });

    // Put file to archived location
    check sftpClient->put(archivedPath, fileContent);
    log:printInfo(string `File copied to archived location: ${archivedPath}`);

    // Delete original file
    check sftpClient->delete(originalFilePath);
    log:printInfo(string `Original file deleted: ${originalFilePath}`);
}
