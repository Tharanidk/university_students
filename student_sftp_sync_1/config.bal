// SFTP Configuration
configurable string sftpHost = ?;
configurable int sftpPort = 22;
configurable string sftpUser = ?;
configurable string sftpPrivateKeyPath = ?;
configurable string sftpWatchPath = ?;

// MySQL Configuration
configurable string mysqlHost = ?;
configurable int mysqlPort = 3306;
configurable string mysqlUser = ?;
configurable string mysqlPassword = ?;
configurable string mysqlDatabase = ?;

// Email Configuration
configurable boolean enableEmail = false;
configurable string smtpHost = "smtp.gmail.com";
configurable int smtpPort = 465;
configurable string smtpUser = ?;
configurable string smtpPassword = ?;
configurable string recipientEmail = ?;
