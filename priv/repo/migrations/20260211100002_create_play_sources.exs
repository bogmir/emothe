defmodule Emothe.Repo.Migrations.CreatePlaySources do
  use Ecto.Migration

  def change do
    create table(:play_sources, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :play_id, references(:plays, type: :binary_id, on_delete: :delete_all), null: false
      add :title, :string
      add :author, :string
      add :editor, :string
      add :note, :text
      add :publisher, :string
      add :pub_place, :string
      add :pub_date, :string
      add :position, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:play_sources, [:play_id])
  end
end
