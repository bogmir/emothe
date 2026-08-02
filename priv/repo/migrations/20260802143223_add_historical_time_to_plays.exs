defmodule Emothe.Repo.Migrations.AddHistoricalTimeToPlays do
  use Ecto.Migration

  def change do
    alter table(:plays) do
      add :historical_time, :string
      add :historical_time_note, :text
    end
  end
end
