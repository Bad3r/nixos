-- Synthetic Duplicati schema-v19 subset that exercises every duplicati-r2-list
-- subcommand. Only tables / views the CLI touches are created; everything else
-- (Block, BlocksetEntry, Remotevolume, BlocklistHash, ...) is omitted because
-- Cut A is metadata-only.

PRAGMA user_version = 19;

CREATE TABLE Configuration (Key TEXT PRIMARY KEY, Value TEXT);
INSERT INTO Configuration VALUES
  ('blocksize', '102400'),
  ('blockhash', 'SHA256'),
  ('Version', '19');

CREATE TABLE PathPrefix (ID INTEGER PRIMARY KEY, Prefix TEXT NOT NULL UNIQUE);
INSERT INTO PathPrefix VALUES
  (1, '/data/'),
  (2, '/data/sub/'),
  (3, '/data/[1.0.0]/'),
  (4, '/data/1/');

CREATE TABLE FileLookup (
  ID INTEGER PRIMARY KEY,
  PrefixID INTEGER NOT NULL,
  Path TEXT NOT NULL,
  BlocksetID INTEGER,
  MetadataID INTEGER
);
-- BlocksetID -100 is FOLDER_BLOCKSET_ID, -200 is SYMLINK_BLOCKSET_ID per
-- Duplicati's LocalDatabase.cs. Neither value exists in Blockset, so the
-- CLI's stat/history/grep/ls queries must LEFT JOIN to return these rows.
INSERT INTO FileLookup VALUES
  (1, 1, 'one.txt',     101, 201),
  (2, 1, 'two.log',     102, 202),
  (3, 2, 'three.txt',   103, 203),
  (4, 2, '',           -100, 204),  -- /data/sub/ directory entry
  (5, 1, 'link.txt',   -200, 205),  -- symlink at /data/link.txt
  (6, 3, 'literal.txt', 104, 206),
  (7, 4, 'false.txt',   105, 207);

CREATE VIEW File AS
  SELECT FileLookup.ID         AS ID,
         PathPrefix.Prefix || FileLookup.Path AS Path,
         FileLookup.BlocksetID AS BlocksetID,
         FileLookup.MetadataID AS MetadataID
  FROM FileLookup JOIN PathPrefix ON FileLookup.PrefixID = PathPrefix.ID;

CREATE TABLE Blockset (
  ID INTEGER PRIMARY KEY,
  Length INTEGER,
  FullHash TEXT
);
INSERT INTO Blockset VALUES
  (101, 12,        'hash-one'),
  (102, 4096,      'hash-two'),
  (103, 1048576,   'hash-three'),
  (104, 32,        'hash-literal'),
  (105, 32,        'hash-false');

CREATE TABLE Remotevolume (
  ID INTEGER PRIMARY KEY,
  Name TEXT,
  Type TEXT,
  State TEXT
);
INSERT INTO Remotevolume VALUES
  (1, 'duplicati-20260101T000000Z.dlist.zip.aes', 'Files',  'Verified'),
  (2, 'duplicati-20260201T000000Z.dlist.zip.aes', 'Files',  'Verified');

CREATE TABLE Fileset (
  ID INTEGER PRIMARY KEY,
  VolumeID INTEGER,
  Timestamp INTEGER,
  IsFullBackup INTEGER
);
INSERT INTO Fileset VALUES
  (1, 1, 1767225600, 1),  -- 2026-01-01T00:00:00Z
  (2, 2, 1769904000, 0);  -- 2026-02-01T00:00:00Z

CREATE TABLE FilesetEntry (
  FilesetID INTEGER,
  FileID INTEGER,
  Lastmodified INTEGER,
  PRIMARY KEY (FilesetID, FileID)
);
INSERT INTO FilesetEntry VALUES
  (1, 1, 1767200000),
  (1, 2, 1767200100),
  (1, 3, 1767200200),
  (1, 4, 1767200300),  -- /data/sub/ directory entry
  (1, 5, 1767200400),  -- /data/link.txt symlink
  (1, 6, 1767200500),
  (1, 7, 1767200600),
  (2, 1, 1769900000),  -- one.txt appears in both snapshots
  (2, 2, 1769900100),  -- two.log appears in both
  (2, 4, 1769900200),  -- /data/sub/ persists in snapshot 2
  (2, 5, 1769900300),  -- /data/link.txt persists in snapshot 2
  (2, 6, 1769900400),
  (2, 7, 1769900500);
-- three.txt only in snapshot 1; absent from snapshot 2 (deletion).
