import ballerina/log;
import ballerina/lang.runtime;
import ballerina/ftp;

string[] processedFiles = [];
function init() returns error? {
    log:printInfo("=== EPFL Student Data Sync ===");
    log:printInfo(string `Watching: ${sftpHost}:${sftpPort}${sftpWatchPath}`);
}

public function main() returns error? {
    while true {
        do {
            check scanAndProcessFiles();
        } on fail error e {
            log:printError(string `Polling error: ${e.message()}`);
        }
        runtime:sleep(10);
    }
}

function scanAndProcessFiles() returns error? {
    ftp:Client sftpClient = check getSftpClient();
    ftp:FileInfo[] files = check sftpClient->list(sftpWatchPath);

    foreach ftp:FileInfo file in files {
        string fileName = file.name;

        if !(fileName.endsWith(".csv") && fileName.startsWith("EPFL"))|| processedFiles.indexOf(fileName) != ()  {
            continue;
        }

        log:printInfo(string `New file detected: ${fileName}`);
        processedFiles.push(fileName);

        do {
            string startTime = getCurrentTime();
            byte[] csvBytes = check downloadFile(file.pathDecoded);

            if fileName.toLowerAscii().includes("datenaissance") {
                log:printInfo("Processing: Birth Date Join");
                check processBirthDateFile(csvBytes);
            } else if fileName.toLowerAscii().includes("update") {
                log:printInfo("Processing: Incremental Update");
                check processFile(csvBytes, startTime);
            } else {
                log:printInfo("Processing: Initial Load");
                check processFile(csvBytes, startTime);
            }
        } on fail error e {
            log:printError(string `Error processing ${fileName}: ${e.message()}`);
        }
    }
}
