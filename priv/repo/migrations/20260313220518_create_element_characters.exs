defmodule Emothe.Repo.Migrations.CreateElementCharacters do
  use Ecto.Migration

  def up do
    create table(:element_characters, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :element_id, references(:play_elements, type: :binary_id, on_delete: :delete_all), null: false
      add :character_id, references(:characters, type: :binary_id, on_delete: :delete_all), null: false
      add :position, :integer, default: 0, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:element_characters, [:element_id, :character_id])
    create index(:element_characters, [:character_id])

    # Ensure uuid extension is available for data migration
    execute("CREATE EXTENSION IF NOT EXISTS \"pgcrypto\"")

    # Migrate existing speech character_id data to the join table
    execute("""
    INSERT INTO element_characters (id, element_id, character_id, position, inserted_at, updated_at)
    SELECT gen_random_uuid(), id, character_id, 0, NOW(), NOW()
    FROM play_elements
    WHERE character_id IS NOT NULL AND type = 'speech'
    """)

    # Drop the old character_id column
    alter table(:play_elements) do
      remove :character_id
    end
  end

  def down do
    alter table(:play_elements) do
      add :character_id, references(:characters, type: :binary_id, on_delete: :nilify_all)
    end

    # Migrate data back (only first character per element)
    execute("""
    UPDATE play_elements pe
    SET character_id = ec.character_id
    FROM (
      SELECT DISTINCT ON (element_id) element_id, character_id
      FROM element_characters
      ORDER BY element_id, position
    ) ec
    WHERE pe.id = ec.element_id
    """)

    drop table(:element_characters)
  end
end
