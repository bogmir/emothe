defmodule Emothe.Repo.Migrations.CreateCharacters do
  use Ecto.Migration

  def change do
    create table(:characters, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :play_id, references(:plays, type: :binary_id, on_delete: :delete_all), null: false
      add :xml_id, :string, null: false
      add :name, :string, null: false
      add :description, :string
      add :is_hidden, :boolean, default: false
      add :position, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:characters, [:play_id])
    create unique_index(:characters, [:play_id, :xml_id])
  end
end
