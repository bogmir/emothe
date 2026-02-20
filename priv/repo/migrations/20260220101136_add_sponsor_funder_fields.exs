defmodule Emothe.Repo.Migrations.AddSponsorFunderFields do
  use Ecto.Migration

  def change do
    alter table(:plays) do
      add :sponsor, :text
      add :funder, :text
    end
  end
end
