import ballerina/log;
import ballerina/ftp;

// Track files currently being processed and already processed
string[] processingFiles = [];
string[] processedFiles = [];

listener ftp:Listener sftpFileListener = check new ({
    protocol: ftp:SFTP,
    host: sftpHost,
    port: sftpPort,
    auth: {
        credentials: {
            username: sftpUser,
            password: sftpPass
        },
        privateKey: {
            path: sftpPrivateKeyPath,
            password: sftpPrivateKeyPassword
        }
    },
    path: sftpWatchPath,
    pollingInterval: 30,
    fileNamePattern: "(.*)\\.csv"
});

service ftp:Service on sftpFileListener {
    remote function onFileChange(ftp:WatchEvent & readonly watchEvent, ftp:Caller caller) returns error? {
        foreach ftp:FileInfo addedFile in watchEvent.addedFiles {
            string filePath = addedFile.pathDecoded;
            string fileName = addedFile.name;

            // Skip non-EPFL CSV files
            if !(fileName.endsWith(".csv") && fileName.startsWith("EPFL")) {
                continue;
            }

            // Atomically check and mark as processing
            boolean shouldSkip = false;
            lock {
                if processedFiles.indexOf(fileName) != () || processingFiles.indexOf(fileName) != () {
                    shouldSkip = true;
                } else {
                    processingFiles.push(fileName);
                }
            }

            if shouldSkip {
                log:printInfo(string `Skipping (already handled): ${fileName}`);
                continue;
            }

            log:printInfo(string `New file detected: ${fileName}`);

            do {
                string startTime = getCurrentTime();
                byte[] csvBytes = check downloadFile(filePath);

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

                // Archive the processed file
                check archiveFile(filePath);
                log:printInfo(string `Successfully archived: ${fileName}`);

            } on fail error e {
                log:printError(string `Error processing ${fileName}: ${e.message()}`);
                do {
                    check archiveFile(filePath);
                    log:printInfo(string `File archived despite error: ${fileName}`);
                } on fail error archiveError {
                    log:printError(string `Failed to archive ${fileName}: ${archiveError.message()}`);
                }
            }

            // Mark as fully processed (also under lock)
            lock {
                processedFiles.push(fileName);
            }
        }
    }
}
