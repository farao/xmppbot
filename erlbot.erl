-module(erlbot).
-export([start/0,start/2,start/3]).

-include_lib("exmpp/include/exmpp.hrl").
-include_lib("exmpp/include/exmpp_client.hrl").

-define(DSAKEY,
% [P,Q,G,X,Y]
[
125291458405806132656359067589359619548813745963076608583421766249953089662199221857606631078299209157955115668482477596410980751121874578656051349400417480018749274846898695093837611630224766114084187951146564240972516966321897386819150958516243580367574223114966169599428876379808015807277963797127138774091,
938396729208337336210754730605916646577067765973,
64843482257679025684354756780114872534051874696737982646586247470574635980173786896433366735692208963990033984441567545557810913726724277887108260950261791942724501377534685080532984954438392492681751398049083585945208644589919011508653998497669365676536383184526993597693353432068354991278528769757742344276,
453975385763843215014329903109871118953298568751,
122054975821558354948709844795928052115157985914390821496659352007728801471271725697387454191845464804675137572943213006897667372260873376584514484736399854319133858363274690950262726827901993423360842972413625900021031852377211602035288980885504448867606865693139509261413357933973741329331775017529156724843
]).

start() -> start("marius2", "localhost").
start(LoginName, ServerName) -> start(LoginName, ServerName, 5222).

start(LoginName, ServerName, ServerPort) ->
	Password = getPW(),
	Session = connect(ServerName, ServerPort, LoginName, Password),
	login(Session),
	OTRControl = start_otr(),
	io:format("OTRControl: ~p~n", [OTRControl]),
	process_messages(Session, OTRControl).

getPW() ->
	{ok, Passwort} = io:fread("Passwort: ", "~s"),
	Passwort.

connect(ServerName, Port, LoginName, Password) ->
    application:start(exmpp),
    
	% "handle" for the session
	Session = exmpp_session:start(),
	
	% jid of the bot
    JID = exmpp_jid:make(LoginName, ServerName, random),

    % add login dates to the session for authentication
    exmpp_session:auth_basic_digest(Session, JID, Password),
    
	% connect via tcp
    _StreamId = exmpp_session:connect_TCP(Session, ServerName, Port),
	Session.

login(Session) ->
	%% login using the saved login dates
    exmpp_session:login(Session),

    %% send presence status
    exmpp_session:send_packet(Session,
			      exmpp_presence:set_status(
				exmpp_presence:available(), "Echo Ready")),
	ok.

start_otr() ->
	otr:start(),
	CNF = fun(M) -> io:format("INJECT into NET ~p~n", [M]) end,
	CUF = fun(M) -> io:format("INJECT into USER ~p~n", [M]) end,
	{ok, ControlFun} = otr:create_context([{emit_user, CUF}, {emit_net, CNF}, {dsa, ?DSAKEY}]),
	ControlFun({user, start_otr}),
	ControlFun.

process_messages(Session, OTRControl) ->
	receive
		stop ->
			exmpp_session:stop(Session);
		Message = #received_packet{packet_type=message, raw_packet=Packet} ->
			io:format("Packet: ~p~n", [Message]),
			NewPacket = OTRControl({net, Packet}),
			io:format(" NewPacket: ~p~n", [NewPacket]),
			send_packet(Session, Packet),
			process_messages(Session, OTRControl);
		_ -> process_messages(Session, OTRControl)
	end.

send_packet(Session, Packet) ->
    From = exmpp_xml:get_attribute(Packet, from, <<"unknown">>),
    To = exmpp_xml:get_attribute(Packet, to, <<"unknown">>),
    TmpPacket = exmpp_xml:set_attribute(Packet, from, To),
    TmpPacket2 = exmpp_xml:set_attribute(TmpPacket, to, From),
    NewPacket = exmpp_xml:remove_attribute(TmpPacket2, id),
    exmpp_session:send_packet(Session, NewPacket).
