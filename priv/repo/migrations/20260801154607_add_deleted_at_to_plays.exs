defmodule Emothe.Repo.Migrations.AddDeletedAtToPlays do
  use Ecto.Migration

  def change do
    alter table(:plays) do
      add :deleted_at, :utc_datetime
    end

    # The unique index on plays.code is deliberately left global: an archived play keeps
    # its code reserved, which is what turns a re-import into an update of the same row.
    create index(:plays, [:deleted_at])
  end
end
