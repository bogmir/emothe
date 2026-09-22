defmodule PlaycodeWeb.DemoUIHTML do
  @moduledoc false
  use PlaycodeWeb, :html

  import PlaycodeWeb.Components.StatisticsPanel

  embed_templates "demo_ui_html/*"
end
