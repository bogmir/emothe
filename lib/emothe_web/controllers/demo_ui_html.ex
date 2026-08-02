defmodule EmotheWeb.DemoUIHTML do
  @moduledoc false
  use EmotheWeb, :html

  import EmotheWeb.Components.StatisticsPanel

  embed_templates "demo_ui_html/*"
end
