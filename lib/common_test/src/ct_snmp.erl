%%
%% %CopyrightBegin%
%%
%% SPDX-License-Identifier: Apache-2.0
%%
%% Copyright Ericsson AB 2004-2025. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%
%% %CopyrightEnd%
%%

-module(ct_snmp).
-moduledoc """
`Common Test` user interface module for the `SNMP` application.

The purpose of this module is to simplify SNMP configuration for the test case
writer. Many test cases can use default values for common operations and then no
SNMP configuration files need to be supplied. When it is necessary to change
particular configuration parameters, a subset of the relevant SNMP configuration
files can be passed to `ct_snmp` by `Common Test` configuration files. For more
specialized configuration parameters, a simple SNMP configuration file can be
placed in the test suite data directory. To simplify the test suite,
`Common Test` keeps track of some of the SNMP manager information. This way the
test suite does not have to handle as many input parameters as if it had to
interface wthe OTP SNMP manager directly.

_Configurable SNMP Manager and Agent Parameters:_

Manager configuration:

- **`[{start_manager, boolean()}`** - Optional. Default is `true`.

- **`{users, [{user_name(), [call_back_module(), user_data()]}]}`** - Optional.

- **`{usm_users, [{usm_user_name(), [usm_config()]}]}`** - Optional. SNMPv3
  only.

- **`{managed_agents,[{agent_name(), [user_name(), agent_ip(), agent_port(), [agent_config()]]}]}`** -
  `managed_agents` is optional.

- **`{max_msg_size, integer()}`** - Optional. Default is `484`.

- **`{mgr_port, integer()}`** - Optional. Default is `5000`.

- **`{engine _id, string()}`** - Optional. Default is `"mgrEngine"`.

Agent configuration:

- **`{start_agent, boolean()}`** - Optional. Default is `false`.

- **`{agent_sysname, string()}`** - Optional. Default is `"ct_test"`.

- **`{agent_manager_ip, manager_ip()}`** - Optional. Default is `localhost`.

- **`{agent_vsns, list()}`** - Optional. Default is `[v2]`.

- **`{agent_trap_udp, integer()}`** - Optional. Default is `5000`.

- **`{agent_udp, integer()}`** - Optional. Default is `4000`.

- **`{agent_notify_type, atom()}`** - Optional. Default is `trap`.

- **`{agent_sec_type, sec_type()}`** - Optional. Default is `none`.

- **`{agent_passwd, string()}`** - Optional. Default is `""`.

- **`{agent_engine_id, string()}`** - Optional. Default is `"agentEngine"`.

- **`{agent_max_msg_size, string()}`** - Optional. Default is `484`.

The following parameters represents the SNMP configuration files `context.conf`,
`standard.conf`, `community.conf`, `vacm.conf`, `usm.conf`, `notify.conf`,
`target_addr.conf`, and `target_params.conf`. Notice that all values in
`agent.conf` can be modified by the parameters listed above. All these
configuration files have default values set by the `SNMP` application. These
values can be overridden by suppling a list of valid configuration values or a
file located in the test suites data directory, which can produce a list of
valid configuration values if you apply function `file:consult/1` to the file.

- **`{agent_contexts, [term()] | {data_dir_file, rel_path()}}`** - Optional.

- **`{agent_community, [term()] | {data_dir_file, rel_path()}}`** - Optional.

- **`{agent_sysinfo, [term()] | {data_dir_file, rel_path()}}`** - Optional.

- **`{agent_vacm, [term()] | {data_dir_file, rel_path()}}`** - Optional.

- **`{agent_usm, [term()] | {data_dir_file, rel_path()}}`** - Optional.

- **`{agent_notify_def, [term()] | {data_dir_file, rel_path()}}`** - Optional.

- **`{agent_target_address_def, [term()] | {data_dir_file, rel_path()}}`** -
  Optional.

- **`{agent_target_param_def, [term()] | {data_dir_file, rel_path()}}`** -
  Optional.

Parameter `MgrAgentConfName` in the functions is to be a name you allocate in
your test suite using a `require` statement. Example (where
`MgrAgentConfName = snmp_mgr_agent`):

```erlang
suite() -> [{require, snmp_mgr_agent, snmp}].
```

or

```erlang
ct:require(snmp_mgr_agent, snmp).
```

Notice that USM users are needed for SNMPv3 configuration and are not to be
confused with users.

SNMP traps, inform, and report messages are handled by the user callback module.
For details, see the [`SNMP`](`e:snmp:index.html`) application.

It is recommended to use the `.hrl` files created by the Erlang/OTP MIB compiler
to define the Object Identifiers (OIDs). For example, to get the Erlang node
name from `erlNodeTable` in the OTP-MIB:

```erlang
Oid = ?erlNodeEntry ++ [?erlNodeName, 1]
```

Furthermore, values can be set for `SNMP` application configuration parameters,
`config`, `server`, `net_if`, and so on (for a list of valid parameters and
types, see the [`User's Guide for the SNMP application`](`e:snmp:index.html`)).
This is done by defining a configuration data variable on the following form:

```erlang
{snmp_app, [{manager, [snmp_app_manager_params()]},
            {agent, [snmp_app_agent_params()]}]}.
```

A name for the data must be allocated in the suite using `require` (see the
example above). Pass this name as argument `SnmpAppConfName` to
[`ct_snmp:start/3`](`start/3`). `ct_snmp` specifies default values for some
`SNMP` application configuration parameters (such as `{verbosity,trace}` for
parameter `config`). This set of defaults is merged with the parameters
specified by the user. The user values override `ct_snmp` defaults.
""".

-include("snmp_types.hrl").
-include("inet.hrl").
-include("ct.hrl").

%%% API
-export([start/2, start/3, stop/1, get_values/3, get_next_values/3, set_values/4, 
	 set_info/1, register_users/2, register_agents/2, register_usm_users/2,
	 unregister_users/1, unregister_users/2, unregister_agents/1,
	 unregister_agents/2, unregister_usm_users/1, unregister_usm_users/2,
	 load_mibs/1, unload_mibs/1]).

-type agent_config() :: {Item :: term(), Value :: term()}.
-type agent_ip() :: ip().
-type agent_name() :: atom().
-type agent_port() :: integer().
-type call_back_module() :: atom().
-type error_index() :: integer().
-type error_status() :: noError | atom().
-type ip() :: string() | {integer(), integer(), integer(), integer()}.
-type manager_ip() :: ip().
-type oid() :: [byte()].
-type oids() :: [oid()].
-type rel_path() :: string().
-type sec_type() :: none | minimum | semi.
-type snmp_app_agent_params() :: term().
-type snmp_app_manager_params() :: term().
-type snmpreply() :: {error_status(), error_index(), varbinds()}.
-type user_data() :: term().
-type user_name() :: atom().
-type usm_config() :: {Item :: term(), Value :: term()}.
-type usm_user_name() :: string().
-type value_type() :: o | i | u | g | s.
-type var_and_val() :: {oid(), value_type(), term()}.
-type varbind() :: term().
-type varbinds() :: [varbind()].
-doc """
These data types are described in the documentation for the
[`SNMP`](`e:snmp:index.html`) application.
""".
-type varsandvals() :: [var_and_val()].

-export_type([agent_config/0, agent_ip/0, agent_name/0, agent_port/0,
              call_back_module/0, error_index/0, error_status/0, ip/0,
              manager_ip/0, oid/0, oids/0, rel_path/0, sec_type/0,
              snmp_app_agent_params/0, snmp_app_manager_params/0, snmpreply/0,
              user_data/0, user_name/0, usm_config/0, usm_user_name/0,
              value_type/0, var_and_val/0, varbind/0, varbinds/0, varsandvals/0]).

%% Manager values
-define(CT_SNMP_LOG_FILE, "ct_snmp_set.log").
-define(MGR_PORT, 5000).
-define(MAX_MSG_SIZE, 484).
-define(ENGINE_ID, "mgrEngine").

%% Agent values
-define(AGENT_ENGINE_ID, "agentEngine").
-define(TRAP_UDP, 5000). 
-define(AGENT_UDP, 4000).
-define(CONF_FILE_VER, [v2]).
-define(AGENT_MAX_MSG_SIZE, 484).
-define(AGENT_NOTIFY_TYPE, trap).
-define(AGENT_SEC_TYPE, none).
-define(AGENT_PASSWD, "").
%%%=========================================================================
%%%  API
%%%=========================================================================

-doc(#{equiv => start(Config, MgrAgentConfName, undefined)}).
-spec start(Config, MgrAgentConfName) -> 'ok' | {'error', Reason}
              when Config :: proplists:proplist(),
                   MgrAgentConfName :: atom(),
                   Reason :: term().
start(Config, MgrAgentConfName) ->
    start(Config, MgrAgentConfName, undefined).

-doc """
Starts an SNMP manager and/or agent. In the manager case, registrations of users
and agents, as specified by the configuration `MgrAgentConfName`, are performed.
When using SNMPv3, called USM users are also registered. Users, `usm_users`, and
managed agents can also be registered later using
[`ct_snmp:register_users/2`](`register_users/2`),
[`ct_snmp:register_agents/2`](`register_agents/2`), and
[`ct_snmp:register_usm_users/2`](`register_usm_users/2`).

The agent started is called `snmp_master_agent`. Use
[`ct_snmp:load_mibs/1`](`load_mibs/1`) to load MIBs into the agent.

With `SnmpAppConfName` SNMP applications can be configured with parameters
`config`, `mibs`, `net_if`, and so on. The values are merged with (and possibly
override) default values set by `ct_snmp`.
""".
-spec start(Config, MgrAgentConfName, SnmpAppConfName) -> 'ok' | {'error', Reason}
              when Config :: proplists:proplist(),
                   MgrAgentConfName :: atom(),
                   SnmpAppConfName :: atom(),
                   Reason :: term().
start(Config, MgrAgentConfName, SnmpAppConfName) ->
    StartManager= ct:get_config({MgrAgentConfName, start_manager}, true),
    StartAgent = ct:get_config({MgrAgentConfName, start_agent}, false),
   
    SysName = ct:get_config({MgrAgentConfName, agent_sysname}, "ct_test"),
    {ok, HostName} = inet:gethostname(),
    {ok, Addr} = inet:getaddr(HostName, inet),
    IP = tuple_to_list(Addr),
    AgentManagerIP = ct:get_config({MgrAgentConfName, agent_manager_ip}, IP),
    
    prepare_snmp_env(),
    setup_agent(StartAgent, MgrAgentConfName, SnmpAppConfName, 
		Config, SysName, AgentManagerIP, IP),
    setup_manager(StartManager, MgrAgentConfName, SnmpAppConfName, 
		  Config, AgentManagerIP),
    ok = start_application(snmp),

    manager_register(StartManager, MgrAgentConfName).

start_application(App) ->
    case application:start(App) of
        {error, {already_started, App}} ->
            ok;
        Else ->
            Else
    end.
 
-doc """
Stops the SNMP manager and/or agent, and removes all files created.
""".
-spec stop(Config) -> 'ok'
              when Config :: proplists:proplist().
stop(Config) ->
    PrivDir = ?config(priv_dir, Config),
    ok = application:stop(snmp),
    ok = application:stop(mnesia),
    MgrDir =  filename:join(PrivDir,"mgr"),
    ConfDir = filename:join(PrivDir, "conf"),
    DbDir = filename:join(PrivDir,"db"),
    catch del_dir(MgrDir),
    catch del_dir(ConfDir),
    catch del_dir(DbDir),
    ok.
    
    
-doc """
Issues a synchronous SNMP `get` request.
""".
-spec get_values(Agent, Oids, MgrAgentConfName) -> SnmpReply
              when Agent :: agent_name(),
                   Oids :: oids(),
                   MgrAgentConfName :: atom(),
                   SnmpReply :: snmpreply().
get_values(Agent, Oids, MgrAgentConfName) ->
    [Uid | _] = agent_conf(Agent, MgrAgentConfName),
    {ok, SnmpReply, _} = snmpm:sync_get2(Uid, target_name(Agent), Oids),
    SnmpReply.

-doc """
Issues a synchronous SNMP `get next` request.
""".
-spec get_next_values(Agent, Oids, MgrAgentConfName) -> SnmpReply
              when Agent :: agent_name(),
                   Oids :: oids(),
                   MgrAgentConfName :: atom(),
                   SnmpReply :: snmpreply().
get_next_values(Agent, Oids, MgrAgentConfName) ->
    [Uid | _] = agent_conf(Agent, MgrAgentConfName),
    {ok, SnmpReply, _} = snmpm:sync_get_next2(Uid, target_name(Agent), Oids),
    SnmpReply.

-doc """
Issues a synchronous SNMP `set` request.
""".
-spec set_values(Agent, VarsAndVals, MgrAgentConfName, Config) -> SnmpReply
              when Agent :: agent_name(),
                   VarsAndVals :: varsandvals(),
                   MgrAgentConfName :: atom(),
                   Config :: proplists:proplist(),
                   SnmpReply :: snmpreply().
set_values(Agent, VarsAndVals, MgrAgentConfName, Config) ->
    PrivDir = ?config(priv_dir, Config),
    [Uid | _] = agent_conf(Agent, MgrAgentConfName),
    Oids = lists:map(fun({Oid, _, _}) -> Oid end, VarsAndVals),
    TargetName = target_name(Agent),
    {ok, SnmpGetReply, _} = snmpm:sync_get2(Uid, TargetName, Oids),
    {ok, SnmpSetReply, _} = snmpm:sync_set2(Uid, TargetName, VarsAndVals),
    case SnmpSetReply of
	{noError, 0, _} when PrivDir /= false ->
	    log(PrivDir, Agent, SnmpGetReply, VarsAndVals);
	_ ->
	    set_failed_or_user_did_not_want_to_log
    end,
    SnmpSetReply.

-doc """
Returns a list of all successful `set` requests performed in the test case in
reverse order. The list contains the involved user and agent, the value before
`set`, and the new value. This is intended to simplify the cleanup in function
`end_per_testcase`, that is, the undoing of the `set` requests and their
possible side-effects.
""".
-spec set_info(Config) -> [{Agent, OldVarsAndVals, NewVarsAndVals}]
              when Config :: proplists:proplist(),
                   Agent :: agent_name(),
                   OldVarsAndVals :: varsandvals(),
                   NewVarsAndVals :: varsandvals().
set_info(Config) ->
    PrivDir = ?config(priv_dir, Config),
    SetLogFile = filename:join(PrivDir, ?CT_SNMP_LOG_FILE),
    case file:consult(SetLogFile) of
	{ok, SetInfo} ->
	    ok = delete_file(SetLogFile),
	    lists:reverse(SetInfo);
	_ ->
	    []
    end.

-doc """
Registers the manager entity (=user) responsible for specific agent(s).
Corresponds to making an entry in `users.conf`.

This function tries to register the specified users, without checking if any of
them exist. To change a registered user, the user must first be unregistered.
""".
-spec register_users(MgrAgentConfName, Users) -> 'ok' | {'error', Reason}
              when MgrAgentConfName :: atom(),
                   Users :: [{Id, [Module | Data]}],
                   Id :: snmpm:user_id(),
                   Module :: user_name(),
                   Data :: user_data(),
                   Reason :: term().
register_users(MgrAgentConfName, Users) ->
    case setup_users(Users) of
	ok ->
	    SnmpVals = ct:get_config(MgrAgentConfName),
	    OldUsers = ct:get_config({MgrAgentConfName,users},[]),
	    NewSnmpVals = lists:keystore(users, 1, SnmpVals,
					 {users, Users ++ OldUsers}),
	    ct_config:update_config(MgrAgentConfName, NewSnmpVals),
	    ok;
	Error ->
	    Error
    end.

-doc """
Explicitly instructs the manager to handle this agent. Corresponds to making an
entry in `agents.conf`.

This function tries to register the specified managed agents, without checking
if any of them exist. To change a registered managed agent, the agent must first
be unregistered.
""".
-spec register_agents(MgrAgentConfName, ManagedAgents) -> 'ok' | {'error', Reason}
              when MgrAgentConfName :: atom(),
                   ManagedAgents :: [{AgentName, [Uid | AgentIp | AgentUdpPort | AgentConf]}],
                   AgentName :: agent_name(),
                   Uid :: snmpm:user_id(),
                   AgentIp :: agent_ip(),
                   AgentUdpPort :: inet:port_number(),
                   AgentConf :: [agent_config()],
                   Reason :: term().
register_agents(MgrAgentConfName, ManagedAgents) ->
    case setup_managed_agents(MgrAgentConfName,ManagedAgents) of
	ok ->
	    SnmpVals = ct:get_config(MgrAgentConfName),
	    OldAgents = ct:get_config({MgrAgentConfName,managed_agents},[]),
	    NewSnmpVals = lists:keystore(managed_agents, 1, SnmpVals,
					 {managed_agents,
					  ManagedAgents ++ OldAgents}),
	    ct_config:update_config(MgrAgentConfName, NewSnmpVals),
	    ok;
	Error ->
	    Error
    end.

-doc """
Explicitly instructs the manager to handle this USM user. Corresponds to making
an entry in `usm.conf`.

This function tries to register the specified users, without checking if any of
them exist. To change a registered user, the user must first be unregistered.
""".
-spec register_usm_users(MgrAgentConfName, UsmUsers) -> 'ok' | {'error', Reason}
              when MgrAgentConfName :: atom(),
                   UsmUsers :: [{UsmUserName, UsmConfig}],
                   UsmUserName :: usm_user_name(),
                   UsmConfig :: [usm_config()],
                   Reason :: term().
register_usm_users(MgrAgentConfName, UsmUsers) ->
    EngineID = ct:get_config({MgrAgentConfName, engine_id}, ?ENGINE_ID),
    case setup_usm_users(UsmUsers, EngineID) of
	ok ->
	    SnmpVals = ct:get_config(MgrAgentConfName),
	    OldUsmUsers = ct:get_config({MgrAgentConfName,usm_users},[]),
	    NewSnmpVals = lists:keystore(usm_users, 1, SnmpVals,
					 {usm_users, UsmUsers ++ OldUsmUsers}),
	    ct_config:update_config(MgrAgentConfName, NewSnmpVals),
	    ok;
	Error ->
	    Error
    end.

-doc """
Unregisters all users.
""".
-spec unregister_users(MgrAgentConfName) -> 'ok'
              when MgrAgentConfName :: atom().
unregister_users(MgrAgentConfName) ->
    Users = [Id || {Id,_} <- ct:get_config({MgrAgentConfName, users},[])],
    unregister_users(MgrAgentConfName,Users).

-doc """
Unregisters the specified users.
""".
-doc(#{since => <<"OTP R16B">>}).
-spec unregister_users(MgrAgentConfName, Users) -> 'ok'
              when MgrAgentConfName :: atom(),
                   Users :: [snmpm:user_id()].
unregister_users(MgrAgentConfName,Users) ->
    takedown_users(Users),
    SnmpVals = ct:get_config(MgrAgentConfName),
    AllUsers = ct:get_config({MgrAgentConfName, users},[]),
    RemainingUsers = lists:filter(fun({Id,_}) ->
					  not lists:member(Id,Users)
				  end,
				  AllUsers),
    NewSnmpVals = lists:keyreplace(users, 1, SnmpVals, {users,RemainingUsers}),
    ct_config:update_config(MgrAgentConfName, NewSnmpVals),
    ok.

-doc """
Unregisters all managed agents.
""".
-spec unregister_agents(MgrAgentConfName) -> 'ok'
              when MgrAgentConfName :: atom().
unregister_agents(MgrAgentConfName) ->    
    ManagedAgents =  [AgentName ||
			 {AgentName, _} <-
			     ct:get_config({MgrAgentConfName,managed_agents},[])],
    unregister_agents(MgrAgentConfName,ManagedAgents).

-doc """
Unregisters the specified managed agents.
""".
-doc(#{since => <<"OTP R16B">>}).
-spec unregister_agents(MgrAgentConfName, ManagedAgents) -> 'ok'
              when MgrAgentConfName :: atom(),
                   ManagedAgents :: [agent_name()].
unregister_agents(MgrAgentConfName,ManagedAgents) ->
    takedown_managed_agents(MgrAgentConfName, ManagedAgents),
    SnmpVals = ct:get_config(MgrAgentConfName),
    AllAgents = ct:get_config({MgrAgentConfName,managed_agents},[]),
    RemainingAgents = lists:filter(fun({Name,_}) ->
					  not lists:member(Name,ManagedAgents)
				   end,
				   AllAgents),
    NewSnmpVals = lists:keyreplace(managed_agents, 1, SnmpVals,
				   {managed_agents,RemainingAgents}),
    ct_config:update_config(MgrAgentConfName, NewSnmpVals),
    ok.

-doc """
Unregisters all USM users.
""".
-doc(#{since => <<"OTP R16B">>}).
-spec unregister_usm_users(MgrAgentConfName) -> 'ok'
              when MgrAgentConfName :: atom().
unregister_usm_users(MgrAgentConfName) ->
    UsmUsers = [Id || {Id,_} <- ct:get_config({MgrAgentConfName, usm_users},[])],
    unregister_usm_users(MgrAgentConfName,UsmUsers).

-doc """
Unregisters the specified USM users.
""".
-doc(#{since => <<"OTP R16B">>}).
-spec unregister_usm_users(MgrAgentConfName, UsmUsers) -> 'ok'
              when MgrAgentConfName :: atom(),
                   UsmUsers :: [usm_user_name()].
unregister_usm_users(MgrAgentConfName,UsmUsers) ->
    EngineID = ct:get_config({MgrAgentConfName, engine_id}, ?ENGINE_ID),
    takedown_usm_users(UsmUsers,EngineID),
    SnmpVals = ct:get_config(MgrAgentConfName),
    AllUsmUsers = ct:get_config({MgrAgentConfName, usm_users},[]),
    RemainingUsmUsers = lists:filter(fun({Id,_}) ->
					     not lists:member(Id,UsmUsers)
				     end,
				     AllUsmUsers),
    NewSnmpVals = lists:keyreplace(usm_users, 1, SnmpVals,
				   {usm_users,RemainingUsmUsers}),
    ct_config:update_config(MgrAgentConfName, NewSnmpVals),
    ok.

-doc """
Loads the MIBs into agent `snmp_master_agent`.
""".
-spec load_mibs(Mibs) -> 'ok' | {'error', Reason}
            when Mibs :: [MibName],
                MibName :: string(),
                Reason         :: {'load aborted at', MibName, InternalReason},
                InternalReason :: 'already_loaded' | term().
load_mibs(Mibs) ->       
    snmpa:load_mibs(snmp_master_agent, Mibs).
 
-doc """
Unloads the MIBs from agent `snmp_master_agent`.
""".
-doc(#{since => <<"OTP R16B">>}).
-spec unload_mibs(Mibs) -> 'ok' | {'error', Reason}
              when Mibs :: [MibName],
                   MibName :: string(),
                   Reason         :: {'unload aborted at', MibName, InternalReason},
                   InternalReason :: 'not_loaded' | term().
unload_mibs(Mibs) ->
    snmpa:unload_mibs(snmp_master_agent, Mibs).

%%%========================================================================
%%% Internal functions
%%%========================================================================
prepare_snmp_env() ->
    %% To make sure application:set_env is not overwritten by any
    %% app-file settings.
    _ = application:load(snmp),
    
    %% Fix for older versions of snmp where there are some
    %% inappropriate default values for always starting an 
    %% agent.
    application:unset_env(snmp, agent).
%%%---------------------------------------------------------------------------
setup_manager(false, _, _, _, _) ->
    ok;
setup_manager(true, MgrConfName, SnmpConfName, Config, IP) ->    
    PrivDir = ?config(priv_dir, Config),
    MaxMsgSize = ct:get_config({MgrConfName,max_msg_size}, ?MAX_MSG_SIZE),
    Port = ct:get_config({MgrConfName,mgr_port}, ?MGR_PORT),
    EngineID = ct:get_config({MgrConfName,engine_id}, ?ENGINE_ID),
    MgrDir =  filename:join(PrivDir,"mgr"),
    %%% Users, Agents and Usms are in test suites register after the
    %%% snmp application is started.
    Users = [],
    Agents = [],
    Usms = [],
    ok = make_dir(MgrDir),
   
    snmp_config:write_manager_snmp_files(MgrDir, IP, Port, MaxMsgSize, 
					 EngineID, Users, Agents, Usms),
    SnmpEnv = merge_snmp_conf([{config, [{dir, MgrDir},{db_dir, MgrDir},
					 {verbosity, trace}]},
			       {server, [{verbosity, trace}]},
			       {net_if, [{verbosity, trace}]},
			       {versions, [v1, v2, v3]}],
			      ct:get_config({SnmpConfName,manager})),
    application:set_env(snmp, manager, SnmpEnv).
%%%---------------------------------------------------------------------------
setup_agent(false,_, _, _, _, _, _) ->
    ok;
setup_agent(true, AgentConfName, SnmpConfName, 
	    Config, SysName, ManagerIP, AgentIP) ->
    ok = start_application(mnesia),
    PrivDir = ?config(priv_dir, Config),
    Vsns = ct:get_config({AgentConfName, agent_vsns}, ?CONF_FILE_VER),
    TrapUdp = ct:get_config({AgentConfName, agent_trap_udp}, ?TRAP_UDP),
    AgentUdp = ct:get_config({AgentConfName, agent_udp}, ?AGENT_UDP),
    NotifType = ct:get_config({AgentConfName, agent_notify_type},
			      ?AGENT_NOTIFY_TYPE),
    SecType = ct:get_config({AgentConfName, agent_sec_type}, ?AGENT_SEC_TYPE),
    Passwd  = ct:get_config({AgentConfName, agent_passwd}, ?AGENT_PASSWD),
    AgentEngineID = ct:get_config({AgentConfName, agent_engine_id}, 
				  ?AGENT_ENGINE_ID),
    AgentMaxMsgSize = ct:get_config({AgentConfName, agent_max_msg_size},
				    ?MAX_MSG_SIZE),
    
    ConfDir = filename:join(PrivDir, "conf"),
    DbDir = filename:join(PrivDir,"db"),
    ok = make_dir(ConfDir),
    ok = make_dir(DbDir),    
    snmp_config:write_agent_snmp_files(ConfDir, Vsns, ManagerIP, TrapUdp, 
				       AgentIP, AgentUdp, SysName, 
				       NotifType, SecType, Passwd,
				       AgentEngineID, AgentMaxMsgSize),

    override_default_configuration(Config, AgentConfName),
    
    SnmpEnv = merge_snmp_conf([{db_dir, DbDir},
			       {config, [{dir, ConfDir},
					 {verbosity, trace}]},
			       {agent_type, master},
			       {agent_verbosity, trace},
			       {net_if, [{verbosity, trace}]},
			       {versions, Vsns}],
			      ct:get_config({SnmpConfName,agent})),
    application:set_env(snmp, agent, SnmpEnv).
%%%---------------------------------------------------------------------------
merge_snmp_conf(Defaults, undefined) ->
    Defaults;
merge_snmp_conf([Def={Key,DefList=[P|_]}|DefParams], UserParams) when is_tuple(P) ->
    case lists:keysearch(Key, 1, UserParams) of
	false ->
	    [Def | merge_snmp_conf(DefParams, UserParams)];
	{value,{Key,UserList}} ->
	    DefList1 = [{SubKey,Val} || {SubKey,Val} <- DefList, 
					lists:keysearch(SubKey, 1, UserList) == false],
	    [{Key,DefList1++UserList} | merge_snmp_conf(DefParams, 
							lists:keydelete(Key, 1, UserParams))]
    end;
merge_snmp_conf([Def={Key,_}|DefParams], UserParams) ->
    case lists:keysearch(Key, 1, UserParams) of
	false ->
	    [Def | merge_snmp_conf(DefParams, UserParams)];
	{value,_} ->
	    merge_snmp_conf(DefParams, UserParams)
    end;
merge_snmp_conf([], UserParams) ->
    UserParams.
			      

%%%---------------------------------------------------------------------------
manager_register(false, _) ->
    ok;
manager_register(true, MgrAgentConfName) ->
    Agents = ct:get_config({MgrAgentConfName, managed_agents}, []),
    Users = ct:get_config({MgrAgentConfName, users}, []),
    UsmUsers = ct:get_config({MgrAgentConfName, usm_users}, []),
    EngineID = ct:get_config({MgrAgentConfName, engine_id}, ?ENGINE_ID),

    setup_usm_users(UsmUsers, EngineID),
    setup_users(Users),
    setup_managed_agents(MgrAgentConfName,Agents).

%%%---------------------------------------------------------------------------
setup_users(Users) ->
    while_ok(fun({Id, [Module, Data]}) ->
		     snmpm:register_user(Id, Module, Data)
	     end, Users).
%%%---------------------------------------------------------------------------   
setup_managed_agents(AgentConfName,Agents) ->
    Fun =
	fun({AgentName, [Uid, AgentIp, AgentUdpPort, AgentConf0]}) ->
		NewAgentIp = case AgentIp of
				 IpTuple when is_tuple(IpTuple) ->
				     IpTuple;
				 HostName when is_list(HostName) ->
				     {ok,Hostent} = inet:gethostbyname(HostName),
				     [IpTuple|_] = Hostent#hostent.h_addr_list,
				     IpTuple
			     end,
		AgentConf =
		    case lists:keymember(engine_id,1,AgentConf0) of
			true ->
			    AgentConf0;
			false ->
			    DefaultEngineID =
				ct:get_config({AgentConfName,agent_engine_id},
					      ?AGENT_ENGINE_ID),
			    [{engine_id,DefaultEngineID}|AgentConf0]
		    end,
		snmpm:register_agent(Uid, target_name(AgentName),
				     [{address,NewAgentIp},{port,AgentUdpPort} |
				      AgentConf])
	end,
    while_ok(Fun,Agents).
%%%---------------------------------------------------------------------------
setup_usm_users(UsmUsers, EngineID)->
    while_ok(fun({UsmUser, Conf}) ->
		     snmpm:register_usm_user(EngineID, UsmUser, Conf)
	     end, UsmUsers).
%%%---------------------------------------------------------------------------
takedown_users(Users) ->
     lists:foreach(fun(Id) ->
			  snmpm:unregister_user(Id)
		   end, Users).
%%%---------------------------------------------------------------------------
takedown_managed_agents(MgrAgentConfName,ManagedAgents) ->
    lists:foreach(fun(AgentName) ->
			  [Uid | _] = agent_conf(AgentName, MgrAgentConfName),
			  snmpm:unregister_agent(Uid, target_name(AgentName))
		  end, ManagedAgents).
%%%---------------------------------------------------------------------------
takedown_usm_users(UsmUsers, EngineID) ->
     lists:foreach(fun(Id) ->
			  snmpm:unregister_usm_user(EngineID, Id)
		   end, UsmUsers).
%%%---------------------------------------------------------------------------  
log(PrivDir, Agent, {_, _, Varbinds}, NewVarsAndVals) ->

    Fun = fun(#varbind{oid = Oid, variabletype = Type, value = Value}) ->
		  {Oid, Type, Value} 
	  end,
    OldVarsAndVals = lists:map(Fun, Varbinds),
    
    File = filename:join(PrivDir, ?CT_SNMP_LOG_FILE),
    {ok, Fd} = file:open(File, [write, append]),
    io:format(Fd, "~p.~n", [{Agent, OldVarsAndVals, NewVarsAndVals}]),
    ok = file:close(Fd),
    ok.
%%%---------------------------------------------------------------------------
del_dir(Dir) ->
    {ok, Files} = file:list_dir(Dir),
    FullPathFiles = lists:map(fun(File) -> filename:join(Dir, File) end,
			      Files),
    lists:foreach(fun file:delete/1, FullPathFiles), 
    ok = delete_dir(Dir),
    ok.
%%%---------------------------------------------------------------------------
agent_conf(Agent, MgrAgentConfName) ->
    Agents = ct:get_config({MgrAgentConfName, managed_agents}),
    case lists:keysearch(Agent, 1, Agents) of
	{value, {Agent, AgentConf}} ->
	    AgentConf;
	_ ->
	    exit({error, {unknown_agent, Agent, Agents}})
    end.
%%%---------------------------------------------------------------------------
override_default_configuration(Config, MgrAgentConfName) ->
    override_contexts(Config,
		      ct:get_config({MgrAgentConfName, agent_contexts}, undefined)),
    override_community(Config,
		       ct:get_config({MgrAgentConfName, agent_community}, undefined)),
    override_sysinfo(Config,
		     ct:get_config({MgrAgentConfName, agent_sysinfo}, undefined)),
    override_vacm(Config,
		  ct:get_config({MgrAgentConfName, agent_vacm}, undefined)),
    override_usm(Config,
		 ct:get_config({MgrAgentConfName, agent_usm}, undefined)),
    override_notify(Config,
		    ct:get_config({MgrAgentConfName, agent_notify_def}, undefined)),
    override_target_address(Config,
			    ct:get_config({MgrAgentConfName, 
					   agent_target_address_def}, 
					  undefined)),
    override_target_params(Config, 
			   ct:get_config({MgrAgentConfName, agent_target_param_def},
					 undefined)).

%%%---------------------------------------------------------------------------
override_contexts(_, undefined) ->
    ok;

override_contexts(Config, {data_dir_file, File}) ->
    Dir = ?config(data_dir, Config),
    FullPathFile = filename:join(Dir, File),
    {ok, ContextInfo} = file:consult(FullPathFile),
    override_contexts(Config, ContextInfo);

override_contexts(Config, Contexts) ->
    Dir = filename:join(?config(priv_dir, Config),"conf"),
    File = filename:join(Dir,"context.conf"),
    ok = delete_file(File),
    ok = snmp_config:write_agent_context_config(Dir, "", Contexts).
		
%%%---------------------------------------------------------------------------
override_sysinfo(_, undefined) ->
    ok;

override_sysinfo(Config, {data_dir_file, File}) ->
    Dir = ?config(data_dir, Config),
    FullPathFile = filename:join(Dir, File),
    {ok, SysInfo} = file:consult(FullPathFile),
    override_sysinfo(Config, SysInfo);

override_sysinfo(Config, SysInfo) ->   
    Dir = filename:join(?config(priv_dir, Config),"conf"),
    File = filename:join(Dir,"standard.conf"),
    ok = delete_file(File),
    ok = snmp_config:write_agent_standard_config(Dir, "", SysInfo).

%%%---------------------------------------------------------------------------
override_target_address(_, undefined) ->
    ok;
override_target_address(Config, {data_dir_file, File}) ->
    Dir = ?config(data_dir, Config),
    FullPathFile = filename:join(Dir, File),
    {ok, TargetAddressConf} = file:consult(FullPathFile),
    override_target_address(Config, TargetAddressConf);

override_target_address(Config, TargetAddressConf) ->
    Dir = filename:join(?config(priv_dir, Config),"conf"),
    File = filename:join(Dir,"target_addr.conf"),
    ok = delete_file(File),
    ok = snmp_config:write_agent_target_addr_config(Dir, "", TargetAddressConf).


%%%---------------------------------------------------------------------------
override_target_params(_, undefined) ->
    ok;
override_target_params(Config, {data_dir_file, File}) ->
    Dir = ?config(data_dir, Config),
    FullPathFile = filename:join(Dir, File),
    {ok, TargetParamsConf} = file:consult(FullPathFile),
    override_target_params(Config, TargetParamsConf);

override_target_params(Config, TargetParamsConf) ->
    Dir = filename:join(?config(priv_dir, Config),"conf"),
    File = filename:join(Dir,"target_params.conf"),
    ok = delete_file(File),
    ok = snmp_config:write_agent_target_params_config(Dir, "", TargetParamsConf).

%%%---------------------------------------------------------------------------
override_notify(_, undefined) ->
    ok;
override_notify(Config, {data_dir_file, File}) ->
    Dir = ?config(data_dir, Config),
    FullPathFile = filename:join(Dir, File),
    {ok, NotifyConf} = file:consult(FullPathFile),
    override_notify(Config, NotifyConf);

override_notify(Config, NotifyConf) ->
    Dir = filename:join(?config(priv_dir, Config),"conf"),
    File = filename:join(Dir,"notify.conf"),
    ok = delete_file(File),
    ok = snmp_config:write_agent_notify_config(Dir, "", NotifyConf).

%%%---------------------------------------------------------------------------
override_usm(_, undefined) ->
    ok;
override_usm(Config, {data_dir_file, File}) ->
    Dir = ?config(data_dir, Config),
    FullPathFile = filename:join(Dir, File),
    {ok, UsmConf} = file:consult(FullPathFile),
    override_usm(Config, UsmConf);

override_usm(Config, UsmConf) ->
    Dir = filename:join(?config(priv_dir, Config),"conf"),
    File = filename:join(Dir,"usm.conf"),
    ok = delete_file(File),
    ok = snmp_config:write_agent_usm_config(Dir, "", UsmConf).

%%%--------------------------------------------------------------------------
override_community(_, undefined) ->
    ok;
override_community(Config, {data_dir_file, File}) ->
    Dir = ?config(data_dir, Config),
    FullPathFile = filename:join(Dir, File),
    {ok, CommunityConf} = file:consult(FullPathFile),
    override_community(Config, CommunityConf);

override_community(Config, CommunityConf) ->
    Dir = filename:join(?config(priv_dir, Config),"conf"),
    File = filename:join(Dir,"community.conf"),
    ok = delete_file(File),
    ok = snmp_config:write_agent_community_config(Dir, "", CommunityConf).
   
%%%---------------------------------------------------------------------------

override_vacm(_, undefined) ->
    ok;
override_vacm(Config, {data_dir_file, File}) ->
    Dir = ?config(data_dir, Config),
    FullPathFile = filename:join(Dir, File),
    {ok, VacmConf} = file:consult(FullPathFile),
    override_vacm(Config, VacmConf);

override_vacm(Config, VacmConf) ->
    Dir = filename:join(?config(priv_dir, Config),"conf"),
    File = filename:join(Dir,"vacm.conf"),
    ok = delete_file(File),
    ok = snmp_config:write_agent_vacm_config(Dir, "", VacmConf).

%%%---------------------------------------------------------------------------

target_name(Agent) ->
    atom_to_list(Agent).

while_ok(Fun,[H|T]) ->
    case Fun(H) of
	ok -> while_ok(Fun,T);
	Error -> Error
    end;
while_ok(_Fun,[]) ->
    ok.

delete_file(FileName) ->
    case file:delete(FileName) of
        {error, enoent} -> ok;
        Else -> Else
    end.

make_dir(Dir) ->
    case file:make_dir(Dir) of
        {error, eexist} -> ok;
        Else -> Else
    end.

delete_dir(Dir) ->
    case file:del_dir(Dir) of
        {error, enoent} -> ok;
        Else -> Else
    end.
