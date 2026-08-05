defmodule Emothe.Repo.Migrations.AddCompositionDateToPlays do
  use Ecto.Migration

  def change do
    alter table(:plays) do
      add :composition_date_from, :integer
      add :composition_date_to, :integer
      add :composition_date_note, :text
    end
  end
end
