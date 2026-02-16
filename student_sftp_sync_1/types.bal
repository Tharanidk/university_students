// Student record type matching the database schema
type Student record {|
    int id;
    string last_name;
    string first_name;
    string email;
    boolean active;
|};

// CSV record type for parsing CSV files
type StudentCsv record {|
    int id;
    string nom;
    string prenom;
    string email;
    string actif;
|};

type UpsertResult record {|
    int insertions;
    int updates;
    int deactivations;
    int errors;
|};

type ProcessingReport record {|
    int totalCsvRows;
    int validRows;
    int invalidRows;
    int insertions;
    int updates;
    int deactivations;
    int errors;
    string startTime;
    string endTime;
|};

type BirthDateCsv record {|
    int id;
    string nom;
    string prenom;
    string email;
    string datenaissance;
    string actif;
|};

