%% -*- erlang-indent-level: 2 -*-
%%
%% %CopyrightBegin%
%%
%% SPDX-License-Identifier: Apache-2.0
%%
%% Copyright 2004-2010 held by the authors. All Rights Reserved.
%% Copyright Ericsson AB 2009-2025. All Rights Reserved.
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

%%%-------------------------------------------------------------------
%%% File    : dialyzer_cl.erl
%%% Authors : Tobias Lindahl <tobiasl@it.uu.se>
%%%           Kostis Sagonas <kostis@it.uu.se>
%%% Description : The command line interface for the Dialyzer tool.
%%%
%%% Created : 27 Apr 2004 by Tobias Lindahl <tobiasl@it.uu.se>
%%%-------------------------------------------------------------------

-module(dialyzer_cl).
-moduledoc false.

-export([start/1,
         start_report_modules_analyzed/1,
         start_report_modules_changed_and_analyzed/1]).

-include("dialyzer.hrl").
-include_lib("kernel/include/file.hrl").  % needed for #file_info{}

-record(cl_state,
	{backend_pid                      :: pid() | 'undefined',
         code_server     = none           :: 'none'
                                           | dialyzer_codeserver:codeserver(),
	 erlang_mode     = false          :: boolean(),
	 external_calls  = []             :: [{mfa(), warning_info()}],
         external_types  = []             :: [{mfa(), warning_info()}],
	 legal_warnings  = ordsets:new()  :: [dial_warn_tag()],
	 mod_deps        = dict:new()     :: dialyzer_callgraph:mod_deps(),
	 output          = standard_io	  :: io:device(),
	 output_format   = formatted      :: format(),
	 filename_opt    = basename       :: filename_opt(),
         indent_opt      = ?INDENT_OPT    :: iopt(),
         error_location  = ?ERROR_LOCATION :: error_location(),
	 output_plt      = none           :: 'none' | file:filename(),
	 plt_info        = none           :: 'none' | #plt_info{},
	 report_mode     = normal         :: rep_mode(),
	 return_status= ?RET_NOTHING_SUSPICIOUS	:: dial_ret(),
	 stored_warnings = []             :: [raw_warning()]
	}).

%%--------------------------------------------------------------------

-spec start(#options{}) -> {dial_ret(), [dial_warning()]}.

start(Opts) ->
  {{Ret,Warns}, _ModulesAnalyzed} = start_report_modules_analyzed(Opts),
  {Ret,Warns}.

-spec start_report_modules_analyzed(#options{}) -> {{dial_ret(), [dial_warning()]}, [module()]}.

start_report_modules_analyzed(Opts) ->
  {{Ret,Warns}, _ModulesChanged, ModulesAnalyzed} = start_report_modules_changed_and_analyzed(Opts),
  {{Ret,Warns}, ModulesAnalyzed}.

-spec start_report_modules_changed_and_analyzed(#options{}) -> {{dial_ret(), [dial_warning()]}, undefined | [module()], [module()]}.

start_report_modules_changed_and_analyzed(#options{analysis_type = AnalysisType} = Options) ->
  process_flag(trap_exit, true),
  case AnalysisType of
    plt_check  -> check_plt(Options);
    plt_build  -> build_plt(Options);
    plt_add    -> add_to_plt(Options);
    plt_remove -> remove_from_plt(Options);
    succ_typings -> enrich_with_modules_changed(do_analysis(Options), undefined)
  end.

%%--------------------------------------------------------------------

build_plt(Opts) ->
  Opts1 = init_opts_for_build(Opts),
  Files = get_files_from_opts(Opts1),
  Md5 = dialyzer_cplt:compute_md5_from_files(Files),
  PltInfo = #plt_info{files = Md5},
  enrich_with_modules_changed(do_analysis(Files, Opts1, dialyzer_plt:new(), PltInfo), undefined).

init_opts_for_build(Opts) ->
  case Opts#options.output_plt =:= none of
    true ->
      case Opts#options.init_plts of
	[] -> Opts#options{output_plt = get_default_output_plt()};
	[Plt] -> Opts#options{init_plts = [], output_plt = Plt};
        Plts ->
          Msg = io_lib:format("Could not build multiple PLT files: ~ts\n",
                              [format_plts(Plts)]),
          cl_error(Msg)
      end;
    false -> Opts#options{init_plts = []}
  end.

%%--------------------------------------------------------------------

add_to_plt(Opts) ->
  Opts1 = init_opts_for_add(Opts),
  AddFiles = get_files_from_opts(Opts1),
  case Opts1#options.init_plts of
    [] -> plt_common(Opts1, [], AddFiles);
    [_] -> plt_common(Opts1, [], AddFiles);
    PltFiles ->
      Plts = [dialyzer_cplt:from_file(F) || F <- PltFiles],
      % Check merge safety
      _ = dialyzer_cplt:merge_plts_or_report_conflicts(PltFiles, Plts),
      _ = [plt_common(Opts#options{init_plts=[Plt]}, [], AddFiles) || Plt <- PltFiles],
      {{?RET_NOTHING_SUSPICIOUS, []}, [], []}
  end.

init_opts_for_add(Opts) ->
  case Opts#options.output_plt =:= none of
    true ->
      case Opts#options.init_plts of
	[] -> Opts#options{output_plt = get_default_output_plt(),
                           init_plts = get_default_init_plt()};
	[Plt] -> Opts#options{output_plt = Plt};
        Plts ->
          Msg = io_lib:format("Could not add to multiple PLT files: ~ts\n",
                              [format_plts(Plts)]),
          cl_error(Msg)
      end;
    false ->
      case Opts#options.init_plts =:= [] of
	true  -> Opts#options{init_plts = get_default_init_plt()};
	false -> Opts
      end
  end.

check_plt(#options{init_plts = []} = Opts) ->
  Opts1 = init_opts_for_check(Opts),
  report_check(Opts1),
  plt_common(Opts1, [], []);
check_plt(#options{init_plts = Plts} = Opts) ->
  check_plt_aux(Plts, Opts).

check_plt_aux([_] = Plt, Opts) ->
  Opts1 = Opts#options{init_plts = Plt},
  Opts2 = init_opts_for_check(Opts1),
  report_check(Opts2),
  plt_common(Opts2, [], []);
check_plt_aux([Plt|Plts], Opts) ->
  case check_plt_aux([Plt], Opts) of
    {{?RET_NOTHING_SUSPICIOUS, []}, ModulesChanged, ModulesAnalyzed} ->
      {{Ret, Warns}, MoreModulesChanged, MoreModulesAnalyzed} = check_plt_aux(Plts, Opts),
      {{Ret, Warns}, ordsets:union(ModulesChanged, MoreModulesChanged), ordsets:union(ModulesAnalyzed, MoreModulesAnalyzed)};
    {{?RET_DISCREPANCIES, Warns}, ModulesChanged, ModulesAnalyzed} ->
      {{_RET, MoreWarns}, MoreModulesChanged, MoreModulesAnalyzed} = check_plt_aux(Plts, Opts),
      {{?RET_DISCREPANCIES, Warns ++ MoreWarns}, ordsets:union(ModulesChanged, MoreModulesChanged), ordsets:union(ModulesAnalyzed, MoreModulesAnalyzed)}
  end.

init_opts_for_check(Opts) ->
  InitPlt =
    case Opts#options.init_plts of
      []-> get_default_init_plt();
      Plt -> Plt
    end,
  [OutputPlt] = InitPlt,

  Opts#options{files         = [],
	       files_rec     = [],
	       analysis_type = plt_check,
	       defines       = [],
	       from          = byte_code,
	       init_plts     = InitPlt,
	       include_dirs  = [],
	       output_plt    = OutputPlt,
	       use_contracts = true
	      }.

%%--------------------------------------------------------------------

remove_from_plt(Opts) ->
  Opts1 = init_opts_for_remove(Opts),
  Files = get_files_from_opts(Opts1),
  plt_common(Opts1, Files, []).

init_opts_for_remove(Opts) ->
  case Opts#options.output_plt =:= none of
    true ->
      case Opts#options.init_plts of
	[] -> Opts#options{output_plt = get_default_output_plt(),
                           init_plts = get_default_init_plt()};
	[Plt] -> Opts#options{output_plt = Plt};
        Plts ->
          Msg = io_lib:format("Could not remove from multiple PLT files: ~ts\n",
                              [format_plts(Plts)]),
          cl_error(Msg)
      end;
    false ->
      case Opts#options.init_plts =:= [] of
	true  -> Opts#options{init_plts = get_default_init_plt()};
	false -> Opts
      end
  end.

%%--------------------------------------------------------------------

plt_common(#options{init_plts = [InitPlt]} = Opts, RemoveFiles, AddFiles) ->
  case check_plt(Opts, RemoveFiles, AddFiles) of
    ok ->
      case Opts#options.output_plt of
	none -> ok;
	InitPlt -> ok;
	OutPlt ->
	  {ok, Binary} = file:read_file(InitPlt),
	  ok = file:write_file(OutPlt, Binary)
      end,
      case Opts#options.report_mode of
	quiet -> ok;
	_ -> io:put_chars(" yes\n")
      end,
      {{?RET_NOTHING_SUSPICIOUS, []}, [], []};
    {old_version, Md5} ->
      PltInfo = #plt_info{files = Md5},
      Files = [F || {F, _} <- Md5],
      enrich_with_modules_changed(do_analysis(Files, Opts, dialyzer_plt:new(), PltInfo), undefined);
    {differ, Md5, DiffMd5, ModDeps} ->
      report_failed_plt_check(Opts, DiffMd5),
      {AnalFiles, RemovedMods, ModDeps1} =
	expand_dependent_modules(Md5, DiffMd5, ModDeps),
      Plt = clean_plt(InitPlt, RemovedMods),
      ChangedOrRemovedMods = [ChangedOrRemovedMod || {_, ChangedOrRemovedMod} <- DiffMd5],
      case AnalFiles =:= [] of
	true ->
	  %% Only removed stuff. Just write the PLT.
	  dialyzer_cplt:to_file(Opts#options.output_plt, Plt, ModDeps1, #plt_info{files=Md5, mod_deps=ModDeps1}),
	  {{?RET_NOTHING_SUSPICIOUS, []}, ChangedOrRemovedMods, []};
	false ->
	  enrich_with_modules_changed(do_analysis(AnalFiles, Opts, Plt, #plt_info{files=Md5, mod_deps=ModDeps1}), ChangedOrRemovedMods)
      end;
    {error, no_such_file} ->
      Msg = io_lib:format("Could not find the PLT: ~ts~n~s",
			  [InitPlt, default_plt_error_msg()]),
      cl_error(Msg);
    {error, not_valid} ->
      Msg = io_lib:format("The file: ~ts is not a valid PLT file~n~s",
			  [InitPlt, default_plt_error_msg()]),
      cl_error(Msg);
    {error, read_error} ->
      Msg = io_lib:format("Could not read the PLT: ~ts~n~s",
			  [InitPlt, default_plt_error_msg()]),
      cl_error(Msg);
    {error, {no_file_to_remove, F}} ->
      Msg = io_lib:format("Could not remove the file ~ts from the PLT: ~ts~n",
			  [F, InitPlt]),
      cl_error(Msg)
  end.

-spec enrich_with_modules_changed({{Ret :: dial_ret(), Warns :: [dial_warning()]}, Analyzed :: [module()]}, Changed :: undefined | [module()]) ->
    {{dial_ret(), [dial_warning()]}, Changed :: undefined | [module()], Analyzed :: [module()]}.

enrich_with_modules_changed({{Ret,Warns}, Analyzed}, Changed) ->
  {{Ret,Warns}, Changed, Analyzed}.

default_plt_error_msg() ->
  "Use the options:\n"
    "   --build_plt   to build a new PLT; or\n"
    "   --add_to_plt  to add to an existing PLT\n"
    "\n"
    "For example, use a command like the following:\n"
    "   dialyzer --build_plt --apps erts kernel stdlib mnesia\n"
    "Note that building a PLT such as the above may take 20 mins or so\n"
    "\n"
    "If you later need information about other applications, say crypto,\n"
    "you can extend the PLT by the command:\n"
    "  dialyzer --add_to_plt --apps crypto\n"
    "For applications that are not in Erlang/OTP use an absolute file name.\n".

%%--------------------------------------------------------------------

check_plt(#options{init_plts = [Plt]} = Opts, RemoveFiles, AddFiles) ->
  case dialyzer_cplt:check_plt(Plt, RemoveFiles, AddFiles) of
    {old_version, _MD5} = OldVersion ->
      report_old_version(Opts),
      OldVersion;
    {differ, _MD5, _DiffMd5, _ModDeps} = Differ ->
      Differ;
    ok ->
      ok;
    {error, _Reason} = Error ->
      Error
  end.

%%--------------------------------------------------------------------

report_check(#options{report_mode = ReportMode, init_plts = [InitPlt]}) ->
  case ReportMode of
    quiet -> ok;
    _ ->
      io:format("  Checking whether the PLT ~ts is up-to-date...", [InitPlt])
  end.

report_old_version(#options{report_mode = ReportMode, init_plts = [InitPlt]}) ->
  case ReportMode of
    quiet -> ok;
    _ ->
      io:put_chars(" no\n"),
      io:format("    (the PLT ~ts was built with an old version of Dialyzer)\n",
		[InitPlt])
  end.

report_failed_plt_check(#options{analysis_type = AnalType,
				 report_mode = ReportMode}, DiffMd5) ->
  case AnalType =:= plt_check of
    true ->
      case ReportMode of
	quiet -> ok;
	normal -> io:format(" no\n", []);
	verbose -> report_md5_diff(DiffMd5)
      end;
    false -> ok
  end.

report_analysis_start(#options{analysis_type = Type,
			       report_mode = ReportMode,
			       init_plts = InitPlts,
			       output_plt = OutputPlt}) ->
  case ReportMode of
    quiet -> ok;
    _ ->
      io:format("  "),
      case Type of
	plt_add ->
          [InitPlt] = InitPlts,
	  case InitPlt =:= OutputPlt of
	    true -> io:format("Adding information to ~ts...", [OutputPlt]);
	    false -> io:format("Adding information from ~ts to ~ts...",
			       [InitPlt, OutputPlt])
	  end;
	plt_build ->
	  io:format("Creating PLT ~ts ...", [OutputPlt]);
	plt_check ->
	  io:format("Rebuilding the information in ~ts...", [OutputPlt]);
	plt_remove ->
          [InitPlt] = InitPlts,
	  case InitPlt =:= OutputPlt of
	    true -> io:format("Removing information from ~ts...", [OutputPlt]);
	    false -> io:format("Removing information from ~ts to ~ts...",
			       [InitPlt, OutputPlt])
	  end;
	succ_typings -> io:format("Proceeding with analysis...")
      end
  end.

report_elapsed_time(T1, T2, #options{report_mode = ReportMode}) ->
  case ReportMode of
    quiet -> ok;
    _ ->
      ElapsedTime = T2 - T1,
      Mins = ElapsedTime div 60000,
      Secs = (ElapsedTime rem 60000) / 1000,
      io:format(" done in ~wm~.2fs\n", [Mins, Secs])
  end.

report_md5_diff(List) ->
  io:format("    The PLT information is not up to date:\n", []),
  case [Mod || {removed, Mod} <- List] of
    [] -> ok;
    RemovedMods -> io:format("    Removed modules: ~p\n", [RemovedMods])
  end,
  case [Mod || {differ, Mod} <- List] of
    [] -> ok;
    ChangedMods -> io:format("    Changed modules: ~p\n", [ChangedMods])
  end.

%%--------------------------------------------------------------------

get_default_init_plt() ->
  [dialyzer_cplt:get_default_cplt_filename()].

get_default_output_plt() ->
  dialyzer_cplt:get_default_cplt_filename().

%%--------------------------------------------------------------------

format_plts([Plt]) -> Plt;
format_plts([Plt|Plts]) ->
  Plt ++ ", " ++ format_plts(Plts).

%%--------------------------------------------------------------------

do_analysis(Options) ->
  Files = get_files_from_opts(Options),
  case Options#options.init_plts of
    [] -> do_analysis(Files, Options, dialyzer_plt:new(), none);
    PltFiles ->
      Plts = [dialyzer_cplt:from_file(F) || F <- PltFiles],
      Plt = dialyzer_cplt:merge_plts_or_report_conflicts(PltFiles, Plts),
      do_analysis(Files, Options, Plt, none)
  end.

do_analysis(Files, Options, Plt, PltInfo) ->
  assert_writable(Options#options.output_plt),
  report_analysis_start(Options),
  State0 = new_state(),
  State1 = init_output(State0, Options),
  State2 = State1#cl_state{legal_warnings = Options#options.legal_warnings,
			   output_plt = Options#options.output_plt,
			   plt_info = PltInfo,
			   erlang_mode = Options#options.erlang_mode,
			   report_mode = Options#options.report_mode
         },
  AnalysisType = convert_analysis_type(Options#options.analysis_type,
				       Options#options.get_warnings),
  InitAnalysis = #analysis{type = AnalysisType,
			   defines = Options#options.defines,
			   include_dirs = Options#options.include_dirs,
			   files = Files,
			   start_from = Options#options.from,
			   timing = Options#options.timing,
			   plt = Plt,
			   use_contracts = Options#options.use_contracts,
			   callgraph_file = Options#options.callgraph_file,
			   mod_deps_file = Options#options.mod_deps_file,
                           solvers = Options#options.solvers},
  State3 = start_analysis(State2, InitAnalysis),
  {T1, _} = statistics(wall_clock),
  RetAndWarns = cl_loop(State3),
  {T2, _} = statistics(wall_clock),
  report_elapsed_time(T1, T2, Options),
  {RetAndWarns, lists:usort([path_to_mod(F) || F <- Files])}.

-spec convert_analysis_type(anal_type1(), boolean()) -> succ_typings | plt_build.
convert_analysis_type(succ_typings, _) -> succ_typings;
convert_analysis_type(_, true) -> succ_typings;
convert_analysis_type(_, false) -> plt_build.

%%--------------------------------------------------------------------

assert_writable(none) ->
  ok;
assert_writable(PltFile) ->
  case check_if_writable(PltFile) of
    true -> ok;
    false ->
      Msg = io_lib:format("    The PLT file ~ts is not writable", [PltFile]),
      cl_error(Msg)
  end.

check_if_writable(PltFile) ->
  case filelib:is_regular(PltFile) of
    true -> is_writable_file_or_dir(PltFile);
    false ->
      case filelib:is_dir(PltFile) of
        true -> false;
        false ->
          DirName = filename:dirname(PltFile),
          case filelib:is_dir(DirName) of
            false ->
              case filelib:ensure_dir(PltFile) of
                ok ->
                  true;
                {error, _} ->
                  false
              end;
            true ->
              is_writable_file_or_dir(DirName)
          end
      end
  end.

is_writable_file_or_dir(PltFile) ->
  case file:read_file_info(PltFile) of
    {ok, #file_info{access = A}} ->
      (A =:= write) orelse (A =:= read_write);
    {error, _} ->
      false
  end.

%%--------------------------------------------------------------------

clean_plt(PltFile, RemovedMods) ->
  %% Clean the plt from the removed modules.
  Plt = dialyzer_cplt:from_file(PltFile),
  sets:fold(fun(M, AccPlt) -> dialyzer_plt:delete_module(AccPlt, M) end,
	    Plt, RemovedMods).

expand_dependent_modules(Md5, DiffMd5, ModDeps) ->
  ChangedMods = sets:from_list([M || {differ, M} <- DiffMd5]),
  RemovedMods = sets:from_list([M || {removed, M} <- DiffMd5]),
  BigSet = sets:union(ChangedMods, RemovedMods),
  BigList = sets:to_list(BigSet),
  ExpandedSet = expand_dependent_modules_1(BigList, BigSet, ModDeps),
  NewModDeps = dialyzer_callgraph:strip_module_deps(ModDeps, BigSet),
  AnalyzeMods = sets:subtract(ExpandedSet, RemovedMods),
  FilterFun = fun(File) ->
		  Mod = path_to_mod(File),
		  sets:is_element(Mod, AnalyzeMods)
	      end,
  {[F || {F, _} <- Md5, FilterFun(F)], BigSet, NewModDeps}.

expand_dependent_modules_1([Mod|Mods], Included, ModDeps) ->
  case dict:find(Mod, ModDeps) of
    {ok, Deps} ->
      NewDeps = sets:subtract(sets:from_list(Deps), Included),
      case sets:size(NewDeps) =:= 0 of
	true -> expand_dependent_modules_1(Mods, Included, ModDeps);
	false ->
	  NewIncluded = sets:union(Included, NewDeps),
	  expand_dependent_modules_1(sets:to_list(NewDeps) ++ Mods,
				     NewIncluded, ModDeps)
      end;
    error ->
      expand_dependent_modules_1(Mods, Included, ModDeps)
  end;
expand_dependent_modules_1([], Included, _ModDeps) ->
  Included.

path_to_mod(File) ->
  list_to_atom(filename:basename(File, ".beam")).

new_state() ->
  #cl_state{}.

init_output(State0, #options{output_file = OutFile,
			     output_format = OutFormat,
			     filename_opt = FOpt,
                             indent_opt = IOpt,
                             error_location = EOpt}) ->
  State = State0#cl_state{output_format = OutFormat,
                          filename_opt = FOpt,
                          indent_opt = IOpt,
                          error_location = EOpt},
  case OutFile =:= none of
    true ->
      State;
    false ->
      case file:open(OutFile, [write]) of
	{ok, File} ->
          %% Warnings and errors can include Unicode characters.
          ok = io:setopts(File, [{encoding, unicode}]),
	  State#cl_state{output = File};
	{error, Reason} ->
	  Msg = io_lib:format("Could not open output file ~tp, Reason: ~p\n",
			      [OutFile, Reason]),
	  cl_error(State, lists:flatten(Msg))
      end
  end.

-spec maybe_close_output_file(#cl_state{}) -> 'ok'.

maybe_close_output_file(State) ->
  case State#cl_state.output of
    standard_io -> ok;
    File -> ok = file:close(File)
  end.

%% ----------------------------------------------------------------
%%
%%  Main Loop
%%

-define(LOG_CACHE_SIZE, 10).

%%-spec cl_loop(#cl_state{}) ->
cl_loop(State) ->
  cl_loop(State, []).

cl_loop(State, LogCache) ->
  BackendPid = State#cl_state.backend_pid,
  receive
    {BackendPid, log, LogMsg} ->
      %%io:format(State#cl_state.output ,"Log: ~s\n", [LogMsg]),
      cl_loop(State, lists:sublist([LogMsg|LogCache], ?LOG_CACHE_SIZE));
    {BackendPid, warnings, Warnings} ->
      NewState = store_warnings(State, Warnings),
      cl_loop(NewState, LogCache);
    {BackendPid, cserver, CodeServer, _Plt} -> % Plt is ignored
      NewState = State#cl_state{code_server = CodeServer},
      cl_loop(NewState, LogCache);
    {BackendPid, done, NewPlt, _NewDocPlt} ->
      return_value(State, NewPlt);
    {BackendPid, ext_calls, ExtCalls} ->
      cl_loop(State#cl_state{external_calls = ExtCalls}, LogCache);
    {BackendPid, ext_types, ExtTypes} ->
      cl_loop(State#cl_state{external_types = ExtTypes}, LogCache);
    {BackendPid, mod_deps, ModDeps} ->
      NewState = State#cl_state{mod_deps = ModDeps},
      cl_loop(NewState, LogCache);
    {'EXIT', BackendPid, {error, Reason}} ->
      Msg = failed_anal_msg(Reason, LogCache),
      cl_error(State, Msg);
    {'EXIT', BackendPid, Reason} when Reason =/= 'normal' ->
      Msg = failed_anal_msg(io_lib:format("~p", [Reason]), LogCache),
      cl_error(State, Msg);
    _Other ->
      %% io:format("Received ~p\n", [_Other]),
      cl_loop(State, LogCache)
  end.

-spec failed_anal_msg(string(), [_]) -> nonempty_string().

failed_anal_msg(Reason, LogCache) ->
  Msg = "Analysis failed with error:\n" ++ lists:flatten(Reason) ++ "\n",
  case LogCache =:= [] of
    true -> Msg;
    false ->
      Msg ++ "Last messages in the log cache:\n  " ++ format_log_cache(LogCache)
  end.

%%
%% formats the log cache (treating it as a string) for pretty-printing
%%
format_log_cache(LogCache) ->
  Str = lists:append(lists:reverse(LogCache)),
  lists:join("\n  ", string:lexemes(Str, "\n")).

-spec store_warnings(#cl_state{}, [raw_warning()]) -> #cl_state{}.

store_warnings(#cl_state{stored_warnings = StoredWarnings} = St, Warnings) ->
  St#cl_state{stored_warnings = StoredWarnings ++ Warnings}.

-spec cl_error(string()) -> no_return().

cl_error(Msg) ->
  throw({dialyzer_error, lists:flatten(Msg)}).

-spec cl_error(#cl_state{}, string()) -> no_return().

cl_error(State, Msg) ->
  case State#cl_state.output of
    standard_io -> ok;
    Outfile -> io:format(Outfile, "\n~ts\n", [Msg])
  end,
  maybe_close_output_file(State),
  throw({dialyzer_error, lists:flatten(Msg)}).

return_value(#cl_state{code_server = CodeServer,
                       erlang_mode = ErlangMode,
                       mod_deps = ModDeps,
                       output_plt = OutputPlt,
                       plt_info = PltInfo,
                       error_location = EOpt,
                       stored_warnings = StoredWarnings}=State,
             Plt) ->
  UnknownWarnings = unknown_warnings(State),
  %% Just for now:
  case CodeServer =:= none of
    true ->
      ok;
    false ->
      dialyzer_codeserver:delete(CodeServer)
  end,
  case OutputPlt =:= none of
    true ->
      dialyzer_plt:delete(Plt);
    false ->
      dialyzer_cplt:to_file(OutputPlt, Plt, ModDeps, PltInfo)
  end,
  RetValue =
    case StoredWarnings =:= [] andalso UnknownWarnings =:= [] of
      true -> ?RET_NOTHING_SUSPICIOUS;
      false -> ?RET_DISCREPANCIES
    end,
  case ErlangMode of
    false ->
      Fns = [ fun print_warnings/1, fun print_ext_calls/1
            , fun print_ext_types/1, fun maybe_close_output_file/1],
      lists:foreach(fun (F) -> F(State) end, Fns),
      {RetValue, []};
    true ->
      ResultingWarnings = process_warnings(StoredWarnings ++ UnknownWarnings),
      {RetValue, set_warning_id(ResultingWarnings, EOpt)}
  end.

unknown_warnings(State) ->
  [Warning || {_M, Warning} <- unknown_warnings_by_module(State)].

unknown_warnings_by_module(#cl_state{legal_warnings = LegalWarnings} = State) ->
  case ordsets:is_element(?WARN_UNKNOWN, LegalWarnings) of
    true ->
      lists:sort(unknown_functions(State)) ++
        lists:sort(unknown_types(State));
    false -> []
  end.

unknown_functions(#cl_state{ external_calls = Calls
                           , code_server = CodeServer}) ->
  [{Mod, {?WARN_UNKNOWN, WarningInfo, {unknown_function, MFA}}} || { MFA, WarningInfo = {_, _, {Mod, _, _}=WarnMFA}} <- Calls
                                                                   , not dialyzer_codeserver:is_member_meta_info(WarnMFA, CodeServer)].

unknown_types(#cl_state{external_types = Types}) ->
  [{Mod, {?WARN_UNKNOWN, WarningInfo, {unknown_type, MFA}}} ||
    {MFA, WarningInfo = {_, _, {Mod, _, _}}} <- Types].

set_warning_id(Warnings, EOpt) ->
  lists:map(fun({Tag, {File, Location, _MorMFA}, Msg}) ->
                {Tag, {File, set_location(Location, EOpt)}, Msg}
            end, Warnings).

set_location({Line, _}, line) ->
  Line;
set_location(Location, _EOpt) ->
  Location.

print_ext_calls(#cl_state{report_mode = quiet}) ->
  ok;
print_ext_calls(#cl_state{legal_warnings = LegalWarnings}=State) ->
  case ordsets:is_element(?WARN_UNKNOWN, LegalWarnings) of
    true -> print_ext_calls_1(State);
    false -> ok
  end.

print_ext_calls_1(#cl_state{output = Output,
			    external_calls = Calls,
			    stored_warnings = Warnings,
			    output_format = Format}) ->
  case Calls =:= [] of
    true -> ok;
    false ->
      case Warnings =:= [] of
	true -> io:nl(Output); %% Need to do a newline first
	false -> ok
      end,
      Calls1 = limit_unknown(Calls),
      case Format of
	formatted ->
	  io:put_chars(Output, "Unknown functions:\n"),
	  do_print_ext_calls(Output, Calls1, "  ");
	raw ->
	  io:put_chars(Output, "%% Unknown functions:\n"),
	  do_print_ext_calls(Output, Calls1, "%%  ")
      end
  end.

do_print_ext_calls(Output, [{{M,F,A},{File,Location,_FromMFA}}|T], Before) ->
  io:format(Output, "~s~tp:~tp/~p (~ts)\n",
            [Before,M,F,A,file_pos(File, Location)]),
  do_print_ext_calls(Output, T, Before);
do_print_ext_calls(_, [], _) ->
  ok.

print_ext_types(#cl_state{report_mode = quiet}) ->
  ok;
print_ext_types(#cl_state{legal_warnings = LegalWarnings}=State) ->
  case ordsets:is_element(?WARN_UNKNOWN, LegalWarnings) of
    true -> print_ext_types_1(State);
    false -> ok
  end.

print_ext_types_1(#cl_state{output = Output,
                            external_calls = Calls,
                            external_types = Types,
                            stored_warnings = Warnings,
                            output_format = Format}) ->
  case Types =:= [] of
    true -> ok;
    false ->
      case Warnings =:= [] andalso Calls =:= [] of
        true -> io:nl(Output); %% Need to do a newline first
        false -> ok
      end,
      Types1 = limit_unknown(Types),
      case Format of
        formatted ->
          io:put_chars(Output, "Unknown types:\n"),
          do_print_ext_types(Output, Types1, "  ");
        raw ->
          io:put_chars(Output, "%% Unknown types:\n"),
          do_print_ext_types(Output, Types1, "%%  ")
      end
  end.

do_print_ext_types(Output, [{{M,F,A},{File,Location,_}}|T], Before) ->
  io:format(Output, "~s~tp:~tp/~p (~ts)\n",
            [Before,M,F,A,file_pos(File, Location)]),
  do_print_ext_types(Output, T, Before);
do_print_ext_types(_, [], _) ->
  ok.

file_pos(File, 0) ->
  io_lib:format("~ts", [File]);
file_pos(File, Pos) ->
  io_lib:format("~ts:~s", [File, pos(Pos)]).

pos({Line,Col}) ->
    io_lib:format("~w:~w", [Line,Col]);
pos(Line) ->
    io_lib:format("~w", [Line]).

%%
%% Keep one warning per MFA and File. Often too many warnings otherwise.
%%
limit_unknown(Unknowns) ->
  L = [{{MFA, File}, {FromMFA, Line}} || {MFA, {File, Line, FromMFA}} <- Unknowns],
  [{MFA, {File, Line, FromMFA}} || {{MFA, File}, [{FromMFA, Line}|_]} <-
                            dialyzer_utils:family(L)].
%% Keep one warning per MFA. This is how it used to be before Erlang/OTP 24.
%% limit_unknown(Unknowns) ->
%%   F = dialyzer_utils:family(Unknowns),
%%   [{MFA, {File, Line}} || {MFA, [{File, Line}|_]} <- F].

print_warnings(#cl_state{stored_warnings = []}) ->
  ok;
print_warnings(#cl_state{output = Output,
			 output_format = Format,
			 filename_opt = FOpt,
                         indent_opt = IOpt,
                         error_location = EOpt,
			 stored_warnings = Warnings}) ->
  PrWarnings = process_warnings(Warnings),
  case PrWarnings of
    [] -> ok;
    [_|_] ->
      PrWarningsId = set_warning_id(PrWarnings, EOpt),
      S = case Format of
	    formatted ->
              Opts = [{filename_opt, FOpt},
                      {indent_opt, IOpt},
                      {error_location, EOpt}],
	      [dialyzer:format_warning(W, Opts) || W <- PrWarningsId];
	    raw ->
	      [io_lib:format("~tp. \n",
                             [W]) || W <- set_warning_id(PrWarningsId, EOpt)]
	  end,
      io:format(Output, "\n~ts", [S])
  end.

-spec process_warnings([raw_warning()]) -> [raw_warning()].

process_warnings(Warnings) ->
  Warnings1 = lists:keysort(3, Warnings), %% First sort on Warning
  Warnings2 = lists:keysort(2, Warnings1), %% Sort on file/location (and m/mfa..)
  remove_duplicate_warnings(Warnings2, []).

remove_duplicate_warnings([Duplicate, Duplicate|Left], Acc) ->
  remove_duplicate_warnings([Duplicate|Left], Acc);
remove_duplicate_warnings([NotDuplicate|Left], Acc) ->
  remove_duplicate_warnings(Left, [NotDuplicate|Acc]);
remove_duplicate_warnings([], Acc) ->
  lists:reverse(Acc).

get_files_from_opts(Options) ->
  From = Options#options.from,
  Files1 = add_files(Options#options.files, From),
  Files2 = add_files_rec(Options#options.files_rec, From),
  ordsets:union(Files1, Files2).

add_files_rec(Files, From) ->
  add_files(Files, From, true).

add_files(Files, From) ->
  add_files(Files, From, false).

add_files(Files, From, Rec) ->
  Files1 = [filename:absname(F) || F <- Files],
  Files2 = ordsets:from_list(Files1),
  Dirs = ordsets:filter(fun(X) -> filelib:is_dir(X) end, Files2),
  Files3 = ordsets:subtract(Files2, Dirs),
  Extension = case From of
		byte_code -> ".beam";
		src_code -> ".erl"
	      end,
  Fun = add_file_fun(Extension),
  lists:foldl(fun(Dir, Acc) ->
		  filelib:fold_files(Dir, Extension, Rec, Fun, Acc)
	      end, Files3, Dirs).

add_file_fun(Extension) ->
  fun(File, AccFiles) ->
      case filename:extension(File) =:= Extension of
	true ->
	  AbsName = filename:absname(File),
	  ordsets:add_element(AbsName, AccFiles);
	false -> AccFiles
      end
  end.

-spec start_analysis(#cl_state{}, #analysis{}) -> #cl_state{}.

start_analysis(State, Analysis) ->
  Self = self(),
  LegalWarnings = State#cl_state.legal_warnings,
  Fun = fun() ->
	    dialyzer_analysis_callgraph:start(Self, LegalWarnings, Analysis)
	end,
  BackendPid = spawn_link(Fun),
  State#cl_state{backend_pid = BackendPid}.
