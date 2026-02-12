defmodule Emothe.Repo.Migrations.CreatePlayEditorialNotes do
  use Ecto.Migration

  def change do
    create table(:play_editorial_notes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :play_id, references(:plays, type: :binary_id, on_delete: :delete_all), null: false
      add :section_type, :string, null: false
      add :heading, :string
      add :content, :text, null: false
      add :position, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:play_editorial_notes, [:play_id])
  end
end
