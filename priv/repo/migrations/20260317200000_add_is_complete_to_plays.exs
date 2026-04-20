defmodule Emothe.Repo.Migrations.AddIsCompleteToPlays do
  use Ecto.Migration

  def change do
    alter table(:plays) do
      add :is_complete, :boolean, default: false, null: false
    end
  end
end
