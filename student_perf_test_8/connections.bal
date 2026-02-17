import ballerinax/mysql;
import ballerinax/mysql.driver as _;
import ballerina/ftp;

// MySQL Client
final mysql:Client mysqlClient = check new (
    host = mysqlHost,
    port = mysqlPort,
    user = mysqlUser,
    password = mysqlPassword,
    database = mysqlDatabase
);

// SFTP Client for downloading files
function getSftpClient() returns ftp:Client|error {
    return check new ({
        protocol: ftp:SFTP,
        host: sftpHost,
        port: sftpPort,
        auth: {
            privateKey: {
                path: sftpPrivateKeyPath
            },
            credentials: {
                username: sftpUser, 
                password: ""
            }
        }
    });
}
