import ballerina/http;
import ballerina/sql;
import ballerina/log;
import ballerinax/mysql;
import ballerinax/mysql.driver as _;

final mysql:Client mysqlClient = check new (
    host = mysqlHost,
    port = mysqlPort,
    user = mysqlUser,
    password = mysqlPassword,
    database = mysqlDatabase
);

function init() returns error? {
    log:printInfo("=== Student API Service ===");
    log:printInfo(string `Database: ${mysqlHost}:${mysqlPort}/${mysqlDatabase}`);
    log:printInfo("API ready at http://localhost:8080/api/students");
}

service /api on new http:Listener(8080) {

     resource function get students(string? status) returns json|http:InternalServerError {
        do {
            sql:ParameterizedQuery q = `SELECT * FROM students`;
            sql:ParameterizedQuery filterClause = ``;

            if status is string && status.equalsIgnoreCaseAscii("active") {
                filterClause = ` WHERE active = 1`;
            } else if status is string && status.equalsIgnoreCaseAscii("inactive") {
                filterClause = ` WHERE active = 0`;
            }

            sql:ParameterizedQuery finalQ = sql:queryConcat(q, filterClause);

            stream<record {}, sql:Error?> rs = mysqlClient->query(finalQ);
            record {}[] students = check from var row in rs select row;
             return students.toJson();
        } on fail error e {
            log:printError(string `Error: ${e.message()}`);
            return http:INTERNAL_SERVER_ERROR;
        }
    }

     resource function get students/[int id]() returns json|http:NotFound|http:InternalServerError {
        do {
            record {} result = check mysqlClient->queryRow(
                `SELECT * FROM students WHERE id = ${id}`
            );
            return result.toJson();
        } on fail error e {
            if e is sql:NoRowsError {
                return http:NOT_FOUND;
            }
            log:printError(string `Error: ${e.message()}`);
            return http:INTERNAL_SERVER_ERROR;
        }
    }
}
