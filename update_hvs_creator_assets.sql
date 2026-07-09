CREATE TABLE IF NOT EXISTS hvs_creator_assets (
  asset_id INTEGER PRIMARY KEY,
  public_id TEXT NOT NULL UNIQUE,
  asset_name TEXT NOT NULL,
  app_category TEXT NOT NULL, -- e.g., 'Apple Creator Studio', 'Home Automation', 'Utilities'
  app_name TEXT NOT NULL, -- e.g., 'Final Cut Pro', 'Logic Pro', 'Numbers'
  file_type TEXT NOT NULL, -- e.g., '.fcpbundle', '.logicx', '.numbers'
  r2_object_key TEXT UNIQUE, -- Linked if backed up to Cloudflare R2
  local_path_blueprint TEXT, -- Local file system reference path for indexing
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_asset_public_id ON hvs_creator_assets (public_id);
CREATE INDEX IF NOT EXISTS idx_asset_app ON hvs_creator_assets (app_name);
