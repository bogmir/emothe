defmodule Emothe.Repo.Migrations.AddEditorRoleToPlaySources do
  use Ecto.Migration

  def change do
    alter table(:play_sources) do
      add :editor_role, :string
    end
  end
end
