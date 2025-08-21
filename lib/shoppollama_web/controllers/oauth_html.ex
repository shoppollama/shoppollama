defmodule ShoppollamaWeb.OAuthHTML do
  @moduledoc """
  This module contains pages rendered by OAuthController.

  See the `oauth_html` directory for all templates.
  """
  use ShoppollamaWeb, :html

  embed_templates "oauth_html/*"
end
