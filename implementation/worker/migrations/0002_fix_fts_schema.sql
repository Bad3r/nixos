-- Fix FTS5 table schema by removing unused columns
-- The triggers don't populate option_names/option_descriptions, so remove them

-- Drop the old FTS table and triggers
DROP TRIGGER IF EXISTS modules_au;
DROP TRIGGER IF EXISTS modules_ad;
DROP TRIGGER IF EXISTS modules_ai;
DROP TABLE IF EXISTS modules_fts;

-- Create simplified FTS table with only the columns we actually populate
CREATE VIRTUAL TABLE modules_fts USING fts5(
  name,
  namespace,
  description,
  content=modules,
  content_rowid=id,
  tokenize='porter unicode61'
);

-- Recreate triggers to keep FTS index in sync
CREATE TRIGGER modules_ai AFTER INSERT ON modules BEGIN
  INSERT INTO modules_fts(rowid, name, namespace, description)
  VALUES (new.id, new.name, new.namespace, new.description);
END;

CREATE TRIGGER modules_ad AFTER DELETE ON modules BEGIN
  DELETE FROM modules_fts WHERE rowid = old.id;
END;

CREATE TRIGGER modules_au AFTER UPDATE ON modules BEGIN
  UPDATE modules_fts
  SET name = new.name,
      namespace = new.namespace,
      description = new.description
  WHERE rowid = new.id;
END;

-- Rebuild FTS index from existing modules
INSERT INTO modules_fts(rowid, name, namespace, description)
SELECT id, name, namespace, description FROM modules;
