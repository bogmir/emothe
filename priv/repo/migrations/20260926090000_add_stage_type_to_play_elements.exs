defmodule Playcode.Repo.Migrations.AddStageTypeToPlayElements do
  use Ecto.Migration

  # A stage direction's TEI @type (entrance, exit, business, location, setting, mixed,
  # delivery, ...), kept verbatim so it survives the export.
  def change do
    alter table(:play_elements) do
      add :stage_type, :string
    end
  end
end
