defmodule Emothe.Repo.Migrations.ChangeSpeakerLabelToText do
  use Ecto.Migration

  def change do
    alter table(:play_elements) do
      modify :speaker_label, :text, from: :string
    end
  end
end
