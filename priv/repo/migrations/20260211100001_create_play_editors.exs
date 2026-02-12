defmodule Emothe.Repo.Migrations.CreatePlayEditors do
  use Ecto.Migration

  def change do
    create table(:play_editors, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :play_id, references(:plays, type: :binary_id, on_delete: :delete_all), null: false
      add :person_name, :string, null: false
      add :role, :string, null: false
      add :organization, :string
      add :position, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:play_editors, [:play_id])
  end
end
