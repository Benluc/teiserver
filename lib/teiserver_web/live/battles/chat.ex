defmodule TeiserverWeb.Battle.LobbyLive.Chat do
  use TeiserverWeb, :live_view
  alias Phoenix.PubSub
  require Logger

  alias Teiserver.{User, Chat}
  alias Teiserver.Battle.{Lobby, LobbyLib}
  alias Teiserver.Chat.LobbyMessage
  import Central.Helpers.NumberHelper, only: [int_parse: 1]

  @message_count 25

  @flood_protect_window_size 5
  @flood_protect_message_count 5

  @impl true
  def mount(_params, session, socket) do
    socket =
      socket
      |> AuthPlug.live_call(session)
      |> TSAuthPlug.live_call(session)
      |> NotificationPlug.live_call()

    socket = socket
      |> add_breadcrumb(name: "Teiserver", url: "/teiserver")
      |> add_breadcrumb(name: "Battles", url: "/teiserver/battle/lobbies")
      |> assign(:site_menu_active, "teiserver_match")
      |> assign(:menu_override, Routes.ts_general_general_path(socket, :index))
      |> assign(:view_colour, LobbyLib.colours())

    {:ok, socket}
  end

  @impl true
  def handle_params(_, _, %{assigns: %{current_user: nil}} = socket) do
    {:noreply, socket |> redirect(to: Routes.general_page_path(socket, :index))}
  end

  def handle_params(%{"id" => id}, _, socket) do
    current_user = socket.assigns[:current_user]
    battle = Lobby.get_battle!(id)

    :ok = PubSub.subscribe(Central.PubSub, "teiserver_lobby_chat:#{id}")
    :ok = PubSub.subscribe(Central.PubSub, "teiserver_liveview_lobby_updates:#{id}")
    :ok = PubSub.subscribe(Central.PubSub, "teiserver_liveview_lobby_chat:#{id}")
    :ok = PubSub.subscribe(Central.PubSub, "teiserver_user_updates:#{current_user.id}")

    cond do
      battle == nil ->
        index_redirect(socket)

      # Coordinator.call_consul(battle.id, {:request_user_join_lobby, current_user.id}) != {true, nil} ->
      #   index_redirect(socket)

      (battle.locked or battle.password != nil) and not allow?(socket, "teiserver.moderator") ->
        index_redirect(socket)

      true ->
        allowed_to_send = not User.has_mute?(current_user.id)

        bar_user = User.get_user_by_id(socket.assigns.current_user.id)

        messages = Chat.list_lobby_messages(
          search: [
            lobby_guid: battle.tags["server/match/uuid"]
          ],
          limit: @message_count*2,
          order_by: "Newest first"
        )
          |> Enum.map(fn m -> {m.user_id, m.content} end)
          |> Enum.filter(fn {_, msg} ->
            allow_read_message?(msg, socket)
          end)
          |> Enum.take(@message_count)

        {:noreply,
         socket
          |> assign(:message_timestamps, [])
          |> assign(:allowed_to_send, allowed_to_send)
          |> assign(:message_changeset, new_message_changeset())
          |> assign(:bar_user, bar_user)
          |> assign(:page_title, "Show battle - Chat")
          |> add_breadcrumb(name: battle.name, url: "/teiserver/battles/lobbies/#{battle.id}")
          |> assign(:id, int_parse(id))
          |> assign(:battle, battle)
          |> assign(:messages, messages)
          |> assign(:user_map, %{})
          |> update_user_map
        }
    end
  end

  @impl true
  def render(assigns) do
    Phoenix.View.render(TeiserverWeb.Battle.LiveView, "chat.html", assigns)
  end

  @impl true
  def handle_event("send-message", %{
      "lobby_message" => %{"content" => content}
    },
    %{
    assigns: %{current_user: current_user, id: id, message_timestamps: message_timestamps}
  } = socket) do
    content = strip_message(content)
    message_timestamps = update_flood_protection(message_timestamps)

    cond do
      content == "" -> :ok
      not allow_send_message?(content, current_user) ->
        send(self(), {:lobby_chat, :say, :ok, current_user.id, "--- Unable to send messages starting with s:, a:, ! or $ via the web interface ---"})

      flood_protect?(message_timestamps) ->
        send(self(), {:lobby_chat, :say, :ok, current_user.id, "--- FLOOD PROTECTION IN PLACE, PLEAES WAIT BEFORE SENDING ANOTHER MESSAGE ---"})
      true ->
        Lobby.say(current_user.id, "w: #{content}", id)
    end

    {:noreply, socket
      |> assign(:message_changeset, new_message_changeset())
      |> assign(:message_timestamps, message_timestamps)
    }
  end

  @impl true
  def handle_info({:liveview_lobby_chat, :say, userid, message}, socket) do
    send(self(), {:lobby_chat, :say, nil, userid, message})
    {:noreply, socket}
  end

  def handle_info({:lobby_chat, :announce, _lobby_id, _, _}, socket) do
    {:noreply, socket}
  end

  def handle_info({:lobby_chat, _say_or_announce, _lobby_id, userid, message}, socket) do
    {userid, message} = case Regex.run(~r/^<(.*?)> (.+)$/u, message) do
      [_, username, remainder] ->
        userid = User.get_userid(username) || userid
        {userid, "g: #{remainder}"}
      _ ->
        {userid, message}
    end

    if allow_read_message?(message, socket) do
      messages = [{userid, message} | socket.assigns[:messages]]
        |> Enum.take(@message_count)

      {:noreply,
        socket
          |> assign(:messages, messages)
          |> update_user_map
      }
    else
      {:noreply, socket}
    end
  end

  def handle_info({:battle_lobby_throttle, :closed}, socket) do
    {:noreply,
      socket
      |> redirect(to: Routes.ts_battle_lobby_index_path(socket, :index))}
  end

   def handle_info({:liveview_lobby_update, :consul_server_updated, _, _}, socket) do
    # socket = socket
    #   |> get_consul_state

    {:noreply, socket}
  end

  def handle_info({:battle_lobby_throttle, _lobby_changes, _}, socket) do
    {:noreply, socket}
  end

  def handle_info({:liveview_lobby_update, _lobby_changes, _, _}, socket) do
    {:noreply, socket}
  end

  def handle_info({:user_update, _update_type, _userid, _data}, %{assigns: %{id: id}} = socket) do
    {:noreply, socket |> redirect(to: Routes.ts_battle_lobby_chat_path(socket, :chat, id))}
  end

  def handle_info(msg, socket) do
    Logger.warn("No handler in #{__MODULE__} for message #{Kernel.inspect msg}")
    {:noreply, socket}
  end

  defp update_user_map(%{assigns: %{user_map: user_map, messages: messages}} = socket) do
    extra_users = messages
      |> Enum.map(fn {id, _} -> id end)
      |> Enum.uniq
      |> Enum.filter(fn userid -> not Map.has_key?(user_map, userid) end)
      |> Map.new(fn userid -> {userid, User.get_user_by_id(userid)} end)

    socket
      |> assign(:user_map, Map.merge(user_map, extra_users))
  end

  defp allow_read_message?(msg, %{
    assigns: %{current_user: current_user}}) do
    cond do
      allow?(current_user, "teiserver.moderator") -> true
      String.starts_with?(msg, "s:") -> false
      String.starts_with?(msg, "a:") -> false
      true -> true
    end
  end

  defp allow_send_message?(msg, current_user) do
    cond do
      allow?(current_user, "teiserver.moderator") -> true
      String.starts_with?(msg, "g:") -> false
      String.starts_with?(msg, "s:") -> false
      String.starts_with?(msg, "a:") -> false
      String.starts_with?(msg, "!") -> false
      String.starts_with?(msg, "$") -> false
      true -> true
    end
  end

  defp index_redirect(socket) do
    {:noreply, socket |> redirect(to: Routes.ts_battle_lobby_index_path(socket, :index))}
  end

  # Takes the message and strips off assignment stuff plus commands
  defp strip_message(msg) do
    msg
      |> String.trim()
      |> String.slice(0..128)

    cond do
      String.starts_with?(msg, "w:") -> strip_message(msg |> String.replace("w:", ""))
      String.starts_with?(msg, "s:") -> strip_message(msg |> String.replace("s:", ""))
      String.starts_with?(msg, "a:") -> strip_message(msg |> String.replace("a:", ""))
      String.starts_with?(msg, "g:") -> strip_message(msg |> String.replace("g:", ""))
      true -> msg
    end
  end

  defp new_message_changeset() do
    %LobbyMessage{}
      |> LobbyMessage.changeset(%{
        "lobby_guid" => "guid",
        "user_id" => 1,
        "inserted_at" => Timex.now(),
        "content" => ""
      })
  end

  defp update_flood_protection(message_timestamps) do
    now = System.system_time(:second)
    limiter = now - @flood_protect_window_size

    [now | message_timestamps]
      |> Enum.filter(fn cmd_ts -> cmd_ts > limiter end)
  end

  @spec flood_protect?(list()) :: boolean
  defp flood_protect?(message_timestamps) do
    Enum.count(message_timestamps) > @flood_protect_message_count
  end
end
