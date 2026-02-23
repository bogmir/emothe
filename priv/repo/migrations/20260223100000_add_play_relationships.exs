defmodule Emothe.Repo.Migrations.AddPlayRelationships do
  use Ecto.Migration

  def change do
    alter table(:plays) do
      add :parent_play_id, references(:plays, type: :binary_id, on_delete: :nilify_all)
      add :relationship_type, :string
      add :edition_title, :text
    end

    create index(:plays, [:parent_play_id])
  end
end
