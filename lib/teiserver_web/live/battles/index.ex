defmodule TeiserverWeb.Battle.LobbyLive.Index do
  use TeiserverWeb, :live_view
  alias Phoenix.PubSub

  alias Teiserver
  alias Teiserver.Battle
  alias Teiserver.Battle.{Lobby, LobbyLib}


  @impl true
  def mount(_params, session, socket) do
    socket =
      socket
      |> AuthPlug.live_call(session)
      |> TSAuthPlug.live_call(session)
      |> NotificationPlug.live_call()

    lobbies = Lobby.list_lobbies()
      |> Enum.map(fn lobby ->
        players = Battle.get_lobby_player_count(lobby.id)

        Map.merge(lobby, %{
          member_count: Battle.get_lobby_member_count(lobby.id),
          player_count: (if players == :lobby, do: 0, else: players)
        })
      end)
      |> sort_lobbies

    socket = socket
      |> add_breadcrumb(name: "Teiserver", url: "/teiserver")
      |> add_breadcrumb(name: "Battles", url: "/teiserver/battle/lobbies")
      |> assign(:site_menu_active, "teiserver_lobbies")
      |> assign(:view_colour, LobbyLib.colours())
      |> assign(:lobbies, lobbies)
      |> assign(:menu_override, Routes.ts_general_general_path(socket, :index))

    {:ok, socket, layout: {CentralWeb.LayoutView, "standard_live.html"}}
  end

  @impl true
  def handle_params(_, _, %{assigns: %{current_user: nil}} = socket) do
    {:noreply, socket |> redirect(to: Routes.general_page_path(socket, :index))}
  end

  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_info({:global_battle_lobby, :opened, lobby_id}, socket) do
    lobby = live_get_lobby(lobby_id)
    lobbies = [lobby | socket.assigns[:lobbies]]
      |> sort_lobbies

    {:noreply, assign(socket, :lobbies, lobbies)}
  end

  def handle_info({:global_battle_lobby, :closed, lobby_id}, socket) do
    lobbies =
      socket.assigns[:lobbies]
      |> Enum.filter(fn b -> b.id != lobby_id end)
      |> sort_lobbies

    {:noreply, assign(socket, :lobbies, lobbies)}
  end

  def handle_info({:global_battle_lobby, :rename, lobby_id}, socket) do
    lobbies =
      socket.assigns[:lobbies]
      |> Enum.map(fn l ->
        if l.id == lobby_id do
          live_get_lobby(lobby_id)
        else
          l
        end
      end)
      |> sort_lobbies

    {:noreply, assign(socket, :lobbies, lobbies)}
  end

  def handle_info({:global_battle_lobby, :update_battle_info, lobby_id}, socket) do
    lobbies =
      socket.assigns[:lobbies]
      |> Enum.map(fn l ->
        if l.id == lobby_id do
          live_get_lobby(lobby_id)
        else
          l
        end
      end)
      |> sort_lobbies

    {:noreply, assign(socket, :lobbies, lobbies)}
  end

  defp sort_lobbies(lobbies) do
    lobbies
      |> Enum.sort_by(
        fn v -> {v.locked, v.password != nil, -v.member_count, v.name} end,
        &<=/2
      )

      # |> Enum.sort_by(fn v -> v end, &<=/2)
  end

  defp apply_action(socket, :index, _params) do
    :ok = PubSub.subscribe(Central.PubSub, "teiserver_global_battle_lobby_updates")

    socket
      |> assign(:page_title, "Listing Battles")
      |> assign(:battle, nil)
  end

  defp live_get_lobby(lobby_id) do
    lobby = Battle.get_lobby(lobby_id)
    players = Battle.get_lobby_player_count(lobby_id)

    Map.merge(lobby, %{
      member_count: Battle.get_lobby_member_count(lobby_id),
      player_count: (if players == :lobby, do: 0, else: players)
    })
  end
end
