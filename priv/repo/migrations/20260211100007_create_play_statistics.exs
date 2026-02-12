defmodule Emothe.Repo.Migrations.CreatePlayStatistics do
  use Ecto.Migration

  def change do
    create table(:play_statistics, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :play_id, references(:plays, type: :binary_id, on_delete: :delete_all), null: false
      add :data, :map, null: false, default: %{}
      add :computed_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:play_statistics, [:play_id])
  end
end
