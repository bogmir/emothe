defmodule Emothe.Repo.Migrations.ChangeDivisionTitleToText do
  use Ecto.Migration

  def change do
    # EMOTHE0730_LaMariana carries a front-matter <head> longer than 255 characters,
    # which raised Postgrex 22001 on every corpus import. Same precedent as
    # 20260226164241_change_speaker_label_to_text.
    alter table(:play_divisions) do
      modify :title, :text, from: :string
    end
  end
end
