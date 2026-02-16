# Student SFTP Sync - Azure Blob Storage Integration

This Ballerina application watches an SFTP directory on Azure Blob Storage for new CSV files and automatically syncs student data to a MySQL database.

## Features

- **SFTP Listener**: Monitors Azure Blob Storage SFTP endpoint for new CSV files
- **Private Key Authentication**: Secure authentication using SSH private keys
- **Automatic Polling**: Checks for new files every 10 seconds
- **CSV File Processing**: Only processes files with `.csv` extension
- **MySQL Integration**: Automatically creates and populates the students table
- **Error Handling**: Robust error handling with detailed logging

## Prerequisites

1. **MySQL Server** - MySQL 5.7 or higher
2. **Azure Blob Storage** - Azure Storage account with SFTP enabled
3. **SSH Key Pair** - Private key for SFTP authentication
4. **Ballerina** - Ballerina Swan Lake distribution

## Database Schema

The application automatically creates the following table on startup:

```sql
CREATE TABLE IF NOT EXISTS students (
    id INT(6) PRIMARY KEY,
    last_name VARCHAR(50),
    first_name VARCHAR(50),
    email VARCHAR(100),
    active TINYINT(1)
);
```

## Configuration

Create a `Config.toml` file in the project root with the following configuration:

```toml
# SFTP Configuration for Azure Blob Storage
# Format: accountname.blob.core.windows.net
sftpHost = "your_account_name.blob.core.windows.net"
sftpPort = 22
# For local user: accountname.localusername
sftpUser = "your_account_name.localuser"
# Path to your SSH private key file
sftpPrivateKeyPath = "/path/to/your/private_key"
# Directory to watch for new CSV files (relative to user's home directory)
sftpWatchPath = "/student-files/incoming"

# MySQL Database Configuration
mysqlHost = "localhost"
mysqlPort = 3306
mysqlUser = "root"
mysqlPassword = "your_mysql_password"
mysqlDatabase = "university_db"
```

### Azure Blob Storage SFTP Setup

1. **Enable SFTP** on your Azure Storage account (requires hierarchical namespace)
2. **Create a local user** in Azure Portal under Storage Account > SFTP
3. **Generate SSH key pair**:
   ```bash
   ssh-keygen -t rsa -b 4096 -f ~/.ssh/azure_sftp_key
   ```
4. **Upload public key** to Azure Storage SFTP local user configuration
5. **Set permissions** for the user on the container/directory
6. **Update Config.toml** with your private key path

### MySQL Setup

1. **Create database**:
   ```sql
   CREATE DATABASE university_db;
   ```
2. The application will automatically create the `students` table on startup

## CSV File Format

The CSV files must have the following structure with headers:

```csv
id,last_name,first_name,email,active
1,Dupont,Jean,jean.dupont@example.com,true
2,Martin,Marie,marie.martin@example.com,false
3,Bernard,Pierre,pierre.bernard@example.com,1
```

**CSV Requirements:**
- **Header Row**: Must contain: `id`, `last_name`, `first_name`, `email`, `active`
- **id**: Integer value
- **last_name**: String (max 50 characters)
- **first_name**: String (max 50 characters)
- **email**: String (max 100 characters)
- **active**: Boolean value (`true`, `false`, `1`, or `0`)

## Running the Application

```bash
bal run
```

The application will:
1. Connect to MySQL and create the students table
2. Start the SFTP listener
3. Poll the configured directory every 10 seconds
4. Process any new CSV files automatically
5. Insert/update student records in the database

## How It Works

### File Detection
- The SFTP listener polls the configured directory every 10 seconds
- Only files matching the pattern `*.csv` are processed
- When a new file is detected, the `onFileChange` event is triggered

### File Processing
1. **Download**: File content is streamed from SFTP
2. **Parse**: CSV is parsed into Student records
3. **Validate**: Data is validated against the schema
4. **Insert**: Records are inserted/updated in MySQL using `ON DUPLICATE KEY UPDATE`
5. **Log**: Processing results are logged

### Error Handling
- Individual record errors don't stop the entire batch
- Detailed error messages are logged for troubleshooting
- Failed records are logged with their ID and error message

## Monitoring

The application provides detailed logging:

```
[INFO] === Starting SFTP Listener Integration ===
[INFO] Creating students table if not exists...
[INFO] Students table is ready
[INFO] Database initialization complete
[INFO] Watching SFTP directory: universitydemo.blob.core.windows.net:22/student-files/incoming
[INFO] Polling interval: 10 seconds
[INFO] File filter: *.csv
[INFO] New CSV file detected: students_2024.csv
[INFO] Parsing CSV file: ./temp/students_2024.csv
[INFO] Parsed 150 student records from CSV
[INFO] Inserting 150 students into database...
[INFO] Insertion complete: 150 successful, 0 errors
[INFO] Successfully processed file: students_2024.csv
```

## Troubleshooting

### SFTP Connection Issues

**Problem**: Cannot connect to SFTP server
- Verify SFTP is enabled on Azure Storage account
- Check if hierarchical namespace is enabled
- Ensure port 22 is accessible from your network
- Verify the username format: `accountname.localusername`

**Problem**: Authentication failed
- Verify private key path is correct
- Ensure private key has correct permissions (chmod 600)
- Check if public key is uploaded to Azure Storage
- Verify the key format is supported (RSA, ED25519)

### MySQL Connection Issues

**Problem**: Cannot connect to MySQL
- Ensure MySQL server is running
- Verify credentials in Config.toml
- Check if MySQL port (3306) is accessible
- Verify database exists or user has CREATE DATABASE privileges

### CSV Processing Issues

**Problem**: CSV parsing errors
- Ensure CSV has header row with correct column names
- Verify CSV is UTF-8 encoded
- Check for missing or extra columns
- Ensure data types match (id must be integer)

**Problem**: Duplicate key errors
- The application uses `ON DUPLICATE KEY UPDATE` to handle duplicates
- Existing records will be updated with new values
- Check logs for specific error messages

## Production Considerations

1. **File Archiving**: Consider moving processed files to an archive folder
2. **Error Notifications**: Add email/SMS alerts for processing failures
3. **Monitoring**: Integrate with monitoring tools (Prometheus, Grafana)
4. **Scaling**: Use connection pooling for high-volume scenarios
5. **Security**: Store credentials in secure vaults (Azure Key Vault, HashiCorp Vault)
6. **Logging**: Configure log levels and rotation policies
7. **Backup**: Regular database backups before processing

## License

This project is provided as-is for educational and integration purposes.
