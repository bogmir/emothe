defmodule Emothe.Repo.Migrations.AddExtendedMetadataFields do
  use Ecto.Migration

  def change do
    alter table(:plays) do
      add :original_title, :string
      add :licence_url, :string
      add :licence_text, :string
      add :emothe_id, :string
    end

    alter table(:play_sources) do
      add :language, :string
    end
  end
end
