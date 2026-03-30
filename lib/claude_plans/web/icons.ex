defmodule ClaudePlans.Web.Icons do
  @moduledoc false
  use Phoenix.Component

  # Lucide Icons (https://lucide.dev) - MIT License
  # Only the icons we need, inlined as SVG for zero bundle overhead.

  defp svg(assigns) do
    size = assigns[:size] || 16
    class = assigns[:class] || ""

    assigns = assign(assigns, size: size, class: class)

    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      width={@size}
      height={@size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      class={@class}
    >
      {render_slot(@inner_block)}
    </svg>
    """
  end

  attr :size, :integer, default: 16
  attr :class, :string, default: ""

  def icon_help(assigns) do
    ~H"""
    <.svg size={@size} class={@class}>
      <circle cx="12" cy="12" r="10" /><path d="M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3" /><path d="M12 17h.01" />
    </.svg>
    """
  end

  attr :size, :integer, default: 16
  attr :class, :string, default: ""

  def icon_moon(assigns) do
    ~H"""
    <.svg size={@size} class={@class}>
      <path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z" />
    </.svg>
    """
  end

  attr :size, :integer, default: 16
  attr :class, :string, default: ""

  def icon_sun(assigns) do
    ~H"""
    <.svg size={@size} class={@class}>
      <circle cx="12" cy="12" r="4" /><path d="M12 2v2" /><path d="M12 20v2" /><path d="m4.93 4.93 1.41 1.41" /><path d="m17.66 17.66 1.41 1.41" /><path d="M2 12h2" /><path d="M20 12h2" /><path d="m6.34 17.66-1.41 1.41" /><path d="m19.07 4.93-1.41 1.41" />
    </.svg>
    """
  end

  attr :size, :integer, default: 16
  attr :class, :string, default: ""

  def icon_a_down(assigns) do
    ~H"""
    <.svg size={@size} class={@class}>
      <path d="m3 16 4 4 4-4" /><path d="M7 20V4" /><path d="M20 8h-5" /><path d="M15 10V6.5a2.5 2.5 0 0 1 5 0V10" />
    </.svg>
    """
  end

  attr :size, :integer, default: 16
  attr :class, :string, default: ""

  def icon_a_up(assigns) do
    ~H"""
    <.svg size={@size} class={@class}>
      <path d="m3 8 4-4 4 4" /><path d="M7 4v16" /><path d="M20 8h-5" /><path d="M15 10V6.5a2.5 2.5 0 0 1 5 0V10" />
    </.svg>
    """
  end

  attr :size, :integer, default: 16
  attr :class, :string, default: ""

  def icon_columns(assigns) do
    ~H"""
    <.svg size={@size} class={@class}>
      <rect width="18" height="18" x="3" y="3" rx="2" ry="2" /><line x1="12" x2="12" y1="3" y2="21" />
    </.svg>
    """
  end

  attr :size, :integer, default: 16
  attr :class, :string, default: ""

  def icon_x(assigns) do
    ~H"""
    <.svg size={@size} class={@class}>
      <path d="M18 6 6 18" /><path d="m6 6 12 12" />
    </.svg>
    """
  end

  attr :size, :integer, default: 16
  attr :class, :string, default: ""

  def icon_edit(assigns) do
    ~H"""
    <.svg size={@size} class={@class}>
      <path d="M12 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7" /><path d="M18.375 2.625a1 1 0 0 1 3 3l-9.013 9.014a2 2 0 0 1-.853.505l-2.873.84a.5.5 0 0 1-.62-.62l.84-2.873a2 2 0 0 1 .506-.852z" />
    </.svg>
    """
  end

  attr :size, :integer, default: 16
  attr :class, :string, default: ""

  def icon_copy(assigns) do
    ~H"""
    <.svg size={@size} class={@class}>
      <rect width="14" height="14" x="8" y="8" rx="2" ry="2" /><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2" />
    </.svg>
    """
  end

  attr :size, :integer, default: 16
  attr :class, :string, default: ""

  def icon_refresh(assigns) do
    ~H"""
    <.svg size={@size} class={@class}>
      <path d="M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8" /><path d="M21 3v5h-5" /><path d="M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16" /><path d="M8 16H3v5" />
    </.svg>
    """
  end

  attr :size, :integer, default: 16
  attr :class, :string, default: ""

  def icon_folder_plus(assigns) do
    ~H"""
    <.svg size={@size} class={@class}>
      <path d="M12 10v6" /><path d="M9 13h6" /><path d="M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z" />
    </.svg>
    """
  end

  attr :size, :integer, default: 16
  attr :class, :string, default: ""

  def icon_trash(assigns) do
    ~H"""
    <.svg size={@size} class={@class}>
      <path d="M3 6h18" /><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6" /><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2" /><line x1="10" x2="10" y1="11" y2="17" /><line x1="14" x2="14" y1="11" y2="17" />
    </.svg>
    """
  end
end
