%%
%% %CopyrightBegin%
%%
%% SPDX-License-Identifier: Apache-2.0
%%
%% Copyright Ericsson AB 2003-2025. All Rights Reserved.
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
-module(trycatch_SUITE).

-export([all/0, suite/0,groups/0,init_per_suite/1, end_per_suite/1, 
	 init_per_group/2,end_per_group/2,basic/1,lean_throw/1,
	 try_of/1,try_after/1,
	 catch_oops/1,after_oops/1,eclectic/1,rethrow/1,
	 nested_of/1,nested_catch/1,nested_after/1,
	 nested_horrid/1,last_call_optimization/1,bool/1,
	 andalso_orelse/1,get_in_try/1,
	 hockey/1,handle_info/1,catch_in_catch/1,grab_bag/1,
         stacktrace/1,nested_stacktrace/1,raise/1,
         no_return_in_try_block/1,
         expression_export/1,
         throw_opt_crash/1,
         coverage/1,
         throw_opt_funs/1]).

-include_lib("common_test/include/ct.hrl").

suite() -> [{ct_hooks,[ts_install_cth]}].

all() -> 
    [{group,p}].

groups() -> 
    [{p,[parallel],
      [basic,lean_throw,try_of,try_after,catch_oops,
       after_oops,eclectic,rethrow,nested_of,nested_catch,
       nested_after,nested_horrid,last_call_optimization,
       bool,andalso_orelse,get_in_try,
       hockey,handle_info,catch_in_catch,grab_bag,
       stacktrace,nested_stacktrace,raise,
       no_return_in_try_block,expression_export,
       throw_opt_crash,
       coverage,
       throw_opt_funs]}].


init_per_suite(Config) ->
    test_lib:recompile(?MODULE),
    Config.

end_per_suite(_Config) ->
    ok.

init_per_group(_GroupName, Config) ->
    Config.

end_per_group(_GroupName, Config) ->
    Config.



basic(Conf) when is_list(Conf) ->
    2 =
	try my_div(4, 2)
	catch 
            Class:Reason -> {Class,Reason}
	end,
    error =
        try my_div(1, 0)
        catch 
            error:badarith -> error
        end,
    error =
        try 1.0 / zero()
        catch 
            error:badarith -> error
        end,
    ok =
        try my_add(53, atom)
        catch
            error:badarith -> ok
        end,
    exit_nisse =
        try exit(nisse)
	catch 
            exit:nisse -> exit_nisse
        end,
    ok =
        try throw(kalle)
        catch
            kalle -> ok
        end,

    %% Try some stuff where the compiler will optimize away the try.

    V = id({a,variable}),
    V = try V catch nisse -> error end,
    42 = try 42 catch nisse -> error end,
    [V] = try [V] catch nisse -> error end,
    {ok,V} = try {ok,V} catch nisse -> error end,

    %% Same idea, but use an after too.

    V = try V catch nisse -> error after after_call() end,
    after_clean(),
    42 = try 42 after after_call() end,
    after_clean(),
    [V] = try [V] catch nisse -> error after after_call() end,
    after_clean(),
    {ok,V} = try {ok,V} after after_call() end,

    %% Try/of
    ok = try V of
	     {a,variable} -> ok
	 catch nisse -> error
	 end,

    %% Unmatchable clauses.
    try
        throw(thrown)
    catch
        {a,b}={a,b,c} ->                        %Intentionally no match.
            ok;
        thrown ->
            ok
    end,

    ok.

after_call() ->
    put(basic, after_was_called).

after_clean() ->
    after_was_called = erase(basic).
    

lean_throw(Conf) when is_list(Conf) ->
    {throw,kalle} =
        try throw(kalle)
        catch
            Kalle -> {throw,Kalle}
        end,
    {exit,kalle} =
        try exit(kalle)
        catch
            Throw1 -> {throw,Throw1};
	    exit:Reason1 -> {exit,Reason1}
        end,
    {exit,kalle} =
        try exit(kalle)
        catch
	    exit:Reason2 -> {exit,Reason2};
            Throw2 -> {throw,Throw2}
        end,
    {exit,kalle} =
        try try exit(kalle)
            catch
                Throw3 -> {throw,Throw3}
            end
        catch
            exit:Reason3 -> {exit,Reason3}
        end,
    ok.



try_of(Conf) when is_list(Conf) ->
    {ok,{some,content}} =
	try_of_1({value,{good,{some,content}}}),
    {error,[other,content]} =
	try_of_1({value,{bad,[other,content]}}),
    {caught,{exit,{ex,it,[reason]}}} =
	try_of_1({exit,{ex,it,[reason]}}),
    {caught,{throw,[term,{in,a,{tuple}}]}} =
	try_of_1({throw,[term,{in,a,{tuple}}]}),
    {caught,{error,[bad,arg]}} =
	try_of_1({error,[bad,arg]}),
    {caught,{error,badarith}} =
	try_of_1({'div',{1,0}}),
    {caught,{error,badarith}} =
	try_of_1({'add',{a,0}}),
    {caught,{error,badarg}} =
	try_of_1({'abs',x}),
    {caught,{error,function_clause}} =
	try_of_1(illegal),
    {error,{try_clause,{some,other_garbage}}} =
	try try_of_1({value,{some,other_garbage}})
        catch error:Reason -> {error,Reason}
        end,
    ok.

try_of_1(X) ->
    try foo(X) of
        {good,Y} -> {ok,Y};
	{bad,Y} -> {error,Y}
    catch
	Class:Reason ->
             {caught,{Class,Reason}}
    end.

try_after(Conf) when is_list(Conf) ->
    try_after_1(fun try_after_basic/2),
    try_after_1(fun try_after_catch/2),
    try_after_1(fun try_after_complex/2),
    try_after_1(fun try_after_fun/2),
    try_after_1(fun try_after_letrec/2),
    try_after_1(fun try_after_protect/2),
    try_after_1(fun try_after_receive/2),
    try_after_1(fun try_after_receive_timeout/2),
    try_after_1(fun try_after_try/2),
    ok.

try_after_1(TestFun) ->
    {{ok,[some,value],undefined},finalized} =
        TestFun({value,{ok,[some,value]}},finalized),
    {{error,badarith,undefined},finalized} =
        TestFun({'div',{1,0}},finalized),
    {{error,badarith,undefined},finalized} =
        TestFun({'add',{1,a}},finalized),
    {{error,badarg,undefined},finalized} =
        TestFun({'abs',a},finalized),
    {{error,[the,{reason}],undefined},finalized} =
        TestFun({error,[the,{reason}]},finalized),
    {{throw,{thrown,[reason]},undefined},finalized} =
        TestFun({throw,{thrown,[reason]}},finalized),
    {{exit,{exited,{reason}},undefined},finalized} =
        TestFun({exit,{exited,{reason}}},finalized),
    {{error,function_clause,undefined},finalized} =
        TestFun(function_clause,finalized),
    ok =
        try
            TestFun({'add',{1,1}}, finalized)
        catch
            error:{try_clause,2} -> ok
        end,
    finalized = erase(try_after),
    ok =
        try
            try
                foo({exit,[reaso,{n}]})
            after
                put(try_after, finalized)
            end
        catch
            exit:[reaso,{n}] -> ok
        end,
    ok.

-define(TRY_AFTER_TESTCASE(Block),
    erase(try_after),
    Try =
        try foo(X) of
            {ok,Value} -> {ok,Value,get(try_after)}
        catch
            Reason -> {throw,Reason,get(try_after)};
            error:Reason -> {error,Reason,get(try_after)};
            exit:Reason ->  {exit,Reason,get(try_after)}
        after
            Block,
            put(try_after, Y)
        end,
    {Try,erase(try_after)}).

try_after_basic(X, Y) ->
    ?TRY_AFTER_TESTCASE(ok).

try_after_catch(X, Y) ->
    ?TRY_AFTER_TESTCASE((catch put(try_after, Y))).

try_after_complex(X, Y) ->
    %% Large 'after' block, going above the threshold for wrapper functions.
    ?TRY_AFTER_TESTCASE(case get(try_after) of
                            unreachable_0 -> dummy:unreachable_0();
                            unreachable_1 -> dummy:unreachable_1();
                            unreachable_2 -> dummy:unreachable_2();
                            unreachable_3 -> dummy:unreachable_3();
                            unreachable_4 -> dummy:unreachable_4();
                            unreachable_5 -> dummy:unreachable_5();
                            unreachable_6 -> dummy:unreachable_6();
                            unreachable_7 -> dummy:unreachable_7();
                            unreachable_8 -> dummy:unreachable_8();
                            unreachable_9 -> dummy:unreachable_9();
                            _ -> put(try_after, Y)
                        end).

try_after_fun(X, Y) ->
    ?TRY_AFTER_TESTCASE((fun() -> ok end)()).

try_after_letrec(X, Y) ->
    List = lists:duplicate(100, ok),
    ?TRY_AFTER_TESTCASE([L || L <- List]).

try_after_protect(X, Y) ->
    ?TRY_AFTER_TESTCASE(case get(try_after) of
                            N when element(52, N) < 32 -> ok;
                            _ -> ok
                        end).

try_after_receive(X, Y) ->
    Ref = make_ref(),
    self() ! Ref,
    ?TRY_AFTER_TESTCASE(receive
                            Ref -> Ref
                        end).

try_after_receive_timeout(X, Y) ->
    Ref = make_ref(),
    self() ! Ref,
    ?TRY_AFTER_TESTCASE(receive
                            Ref -> Ref
                        after 1000 -> ok
                        end).

try_after_try(X, Y) ->
    ?TRY_AFTER_TESTCASE(try
                            put(try_after, Y)
                        catch
                            _ -> ok
                        end).

catch_oops(Conf) when is_list(Conf) ->
    V = {v,[a,l|u],{e},self()},
    {value,V} = catch_oops_1({value,V}),
    {value,1} = catch_oops_1({'div',{1,1}}),
    {error,badarith} = catch_oops_1({'div',{1,0}}),
    {error,function_clause} = catch_oops_1(function_clause),
    {throw,V} = catch_oops_1({throw,V}),
    {exit,V} = catch_oops_1({exit,V}),
    ok.

catch_oops_1(X) ->
    Ref = make_ref(),
    try try foo({error,Ref})
        catch
            error:Ref ->
	        foo(X)
        end of
        Value -> {value,Value}
    catch
        Class:Data -> {Class,Data}
    end.



after_oops(Conf) when is_list(Conf) ->
    V = {self(),make_ref()},

    {{value,V},V} = after_oops_1({value,V}, {value,V}),
    {{exit,V},V} = after_oops_1({exit,V}, {value,V}),
    {{error,V},undefined} = after_oops_1({value,V}, {error,V}),
    {{error,function_clause},undefined} =
        after_oops_1({exit,V}, function_clause),

    {{value,V},V} = after_oops_2({value,V}, {value,V}),
    {{exit,V},V} = after_oops_2({exit,V}, {value,V}),
    {{error,V},undefined} = after_oops_2({value,V}, {error,V}),
    {{error,function_clause},undefined} =
        after_oops_2({exit,V}, function_clause),

    ok.

after_oops_1(X, Y) ->
    erase(after_oops),
    Try =
        try try foo(X)
            after
                put(after_oops, foo(Y))
            end of
            V -> {value,V}
        catch
            C:D -> {C,D}
        end,
    {Try,erase(after_oops)}.

after_oops_2(X, Y) ->
    %% GH-4859: `raw_raise` never got an edge to its catch block, making
    %% try/catch optimization unsafe.
    erase(after_oops),
    Try =
        try
            try
                foo(X)
            catch E:R:S ->
                erlang:raise(E, R, S)
            after
                put(after_oops, foo(Y))
            end
        of
            V -> {value,V}
        catch
            C:D -> {C,D}
        end,
    {Try,erase(after_oops)}.

eclectic(Conf) when is_list(Conf) ->
    V = {make_ref(),3.1415926535,[[]|{}]},
    {{value,{value,V},V},V} =
	eclectic_1({foo,{value,{value,V}}}, undefined, {value,V}),
    {{'EXIT',{V,[{?MODULE,foo,1,_}|_]}},V} =
	eclectic_1({catch_foo,{error,V}}, undefined, {value,V}),
    {{error,{exit,V},{'EXIT',V}},V} =
	eclectic_1({foo,{error,{exit,V}}}, error, {value,V}),
    {{value,{value,V},V},
	   {'EXIT',{badarith,[{erlang,'+',[0,a],_},{?MODULE,my_add,2,_}|_]}}} =
	eclectic_1({foo,{value,{value,V}}}, undefined, {'add',{0,a}}),
    {{'EXIT',V},V} =
	eclectic_1({catch_foo,{exit,V}}, undefined, {throw,V}),
    {{error,{'div',{1,0}},{'EXIT',{badarith,[{erlang,'div',[1,0],_},{?MODULE,my_div,2,_}|_]}}},
	   {'EXIT',V}} =
	eclectic_1({foo,{error,{'div',{1,0}}}}, error, {exit,V}),
    {{{error,V},{'EXIT',{V,[{?MODULE,foo,1,_}|_]}}},
	   {'EXIT',V}} =
	eclectic_1({catch_foo,{throw,{error,V}}}, undefined, {exit,V}),
    %%
    {{value,{value,{value,V},V}},V} =
	eclectic_2({value,{value,V}}, undefined, {value,V}),
    {{value,{throw,{value,V},V}},V} =
	eclectic_2({throw,{value,V}}, throw, {value,V}),
    {{caught,{'EXIT',V}},undefined} =
	eclectic_2({value,{value,V}}, undefined, {exit,V}),
    {{caught,{'EXIT',{V,[{?MODULE,foo,1,_}|_]}}},undefined} =
	eclectic_2({error,{value,V}}, throw, {error,V}),
    {{caught,{'EXIT',{badarg,[{erlang,abs,[V],_}|_]}}},V} =
	eclectic_2({value,{'abs',V}}, undefined, {value,V}),
    {{caught,{'EXIT',{badarith,[{erlang,'+',[0,a],_},{?MODULE,my_add,2,_}|_]}}},V} =
	eclectic_2({exit,{'add',{0,a}}}, exit, {value,V}),
    {{caught,{'EXIT',V}},undefined} =
	eclectic_2({value,{error,V}}, undefined, {exit,V}),
    {{caught,{'EXIT',{V,[{?MODULE,foo,1,_}|_]}}},undefined} =
	eclectic_2({throw,{'div',{1,0}}}, throw, {error,V}),
    ok.

eclectic_1(X, C, Y) ->
    erase(eclectic),
    Done = make_ref(),
    Try =
        try case X of
		{catch_foo,V} -> catch {Done,foo(V)};
		{foo,V} -> {Done,foo(V)}
	    end of
            {Done,D} -> {value,D,catch foo(D)};
	    {'EXIT',_}=Exit -> Exit;
	    D -> {D,catch foo(D)}
        catch
            C:D -> {C,D,catch foo(D)}
        after
            put(eclectic, catch foo(Y))
        end,
    {Try,erase(eclectic)}.

eclectic_2(X, C, Y) ->
    Done = make_ref(),
    erase(eclectic),
    Catch =
	case 
            catch
		{Done,
		 try foo(X) of
		     V -> {value,V,foo(V)}
		 catch
		     C:D -> {C,D,foo(D)}
		 after
		     put(eclectic, foo(Y))
		 end} of
		{Done,Z} -> {value,Z};
		Z -> {caught,Z}
	    end,
    {Catch,erase(eclectic)}.



rethrow(Conf) when is_list(Conf) ->
    V = {a,[b,{c,self()},make_ref]},
    {value2,value1} =
	rethrow_1({value,V}, V),
    {caught2,{error,V}} =
	rethrow_2({error,V}, undefined),
    {caught2,{exit,V}} =
	rethrow_1({exit,V}, error),
    {caught2,{throw,V}} =
	rethrow_1({throw,V}, undefined),
    {caught2,{throw,V}} =
	rethrow_2({throw,V}, undefined),
    {caught2,{error,badarith}} =
	rethrow_1({'add',{0,a}}, throw),
    {caught2,{error,function_clause}} =
	rethrow_2(function_clause, undefined),
    {caught2,{error,{try_clause,V}}} =
	rethrow_1({value,V}, exit),
    {value2,{caught1,V}} =
	rethrow_1({error,V}, error),
    {value2,{caught1,V}} =
	rethrow_1({exit,V}, exit),
    {value2,caught1} =
	rethrow_2({throw,V}, V),
    ok.

rethrow_1(X, C1) ->
    try try foo(X) of
            C1 -> value1
        catch
            C1:D1 -> {caught1,D1}
        end of
        V2 -> {value2,V2}
    catch
        C2:D2 -> {caught2,{C2,D2}}
    end.

rethrow_2(X, C1) ->
    try try foo(X) of
            C1 -> value1
        catch
            C1 -> caught1 % Implicit class throw:
        end of
        V2 -> {value2,V2}
    catch
        C2:D2 -> {caught2,{C2,D2}}
    end.



nested_of(Conf) when is_list(Conf) ->
    V = {[self()|make_ref()],1.4142136},
    {{value,{value1,{V,x2}}},
     {V,x3},
     {V,x4},
     finalized} =
	nested_of_1({{value,{V,x1}},void,{V,x1}},
		    {value,{V,x2}}, {value,{V,x3}}, {value,{V,x4}}),
    {{caught,{throw,{V,x2}}},
     {V,x3},
     {V,x4},
     finalized} =
	nested_of_1({{value,{V,x1}},void,{V,x1}},
		    {throw,{V,x2}}, {value,{V,x3}}, {value,{V,x4}}),
    {{caught,{error,badarith}},
     undefined,
     {V,x4},
     finalized} =
	nested_of_1({{value,{V,x1}},void,{V,x1}},
		    {throw,{V,x2}}, {'div',{1,0}}, {value,{V,x4}}),
    {{caught,{error,badarith}},
     undefined,
     undefined,
     finalized} =
	nested_of_1({{value,{V,x1}},void,{V,x1}},
		    {throw,{V,x2}}, {'div',{1,0}}, {'add',{0,b}}),
    %%
    {{caught,{error,{try_clause,{V,x1}}}},
     {V,x3},
     {V,x4},
     finalized} =
	nested_of_1({{value,{V,x1}},void,try_clause},
		    void, {value,{V,x3}}, {value,{V,x4}}),
    {{caught,{exit,{V,x3}}},
     undefined,
     {V,x4},
     finalized} =
	nested_of_1({{value,{V,x1}},void,try_clause},
		    void, {exit,{V,x3}}, {value,{V,x4}}),
    {{caught,{throw,{V,x4}}},
     undefined,
     undefined,
     finalized} =
	nested_of_1({{value,{V,x1}},void,try_clause},
		    void, {exit,{V,x3}}, {throw,{V,x4}}),
    %%
    {{value,{caught1,{V,x2}}},
     {V,x3},
     {V,x4},
     finalized} =
	nested_of_1({{error,{V,x1}},error,{V,x1}},
		    {value,{V,x2}}, {value,{V,x3}}, {value,{V,x4}}),
    {{caught,{error,badarith}},
     {V,x3},
     {V,x4},
     finalized} =
	nested_of_1({{error,{V,x1}},error,{V,x1}},
		    {'add',{1,c}}, {value,{V,x3}}, {value,{V,x4}}),
    {{caught,{error,badarith}},
     undefined,
     {V,x4},
     finalized} =
	nested_of_1({{error,{V,x1}},error,{V,x1}},
		    {'add',{1,c}}, {'div',{17,0}}, {value,{V,x4}}),
    {{caught,{error,badarg}},
     undefined,
     undefined,
     finalized} =
	nested_of_1({{error,{V,x1}},error,{V,x1}},
		    {'add',{1,c}}, {'div',{17,0}}, {'abs',V}),
    %%
    {{caught,{error,badarith}},
     {V,x3},
     {V,x4},
     finalized} =
	nested_of_1({{'add',{2,c}},rethrow,void},
		    void, {value,{V,x3}}, {value,{V,x4}}),
    {{caught,{error,badarg}},
     undefined,
     {V,x4},
     finalized} =
	nested_of_1({{'add',{2,c}},rethrow,void},
		    void, {'abs',V}, {value,{V,x4}}),
    {{caught,{error,function_clause}},
     undefined,
     undefined,
     finalized} =
	nested_of_1({{'add',{2,c}},rethrow,void},
		    void, {'abs',V}, function_clause),
    ok.

nested_of_1({X1,C1,V1},
	    X2, X3, X4) ->
    erase(nested3),
    erase(nested4),
    erase(nested),
    Self = self(),
    Try =
	try
            try self()
            of
                Self ->
                    try 
                        foo(X1) 
	            of
	                V1 -> {value1,foo(X2)}
                    catch
                        C1:V1 -> {caught1,foo(X2)}
	            after
                        put(nested3, foo(X3))
                    end
            after
                put(nested4, foo(X4))
            end
        of
            V -> {value,V}
        catch
            C:D -> {caught,{C,D}}
        after
            put(nested, finalized)
	end,
    {Try,erase(nested3),erase(nested4),erase(nested)}.



nested_catch(Conf) when is_list(Conf) ->
    V = {[make_ref(),1.4142136,self()]},
    {{value,{value1,{V,x2}}},
     {V,x3},
     {V,x4},
     finalized} =
	nested_catch_1({{value,{V,x1}},void,{V,x1}},
		       {value,{V,x2}}, {value,{V,x3}}, {value,{V,x4}}),
    {{caught,{throw,{V,x2}}},
     {V,x3},
     {V,x4},
     finalized} =
	nested_catch_1({{value,{V,x1}},void,{V,x1}},
		       {throw,{V,x2}}, {value,{V,x3}}, {value,{V,x4}}),
    {{caught,{error,badarith}},
     undefined,
     {V,x4},
     finalized} =
	nested_catch_1({{value,{V,x1}},void,{V,x1}},
		       {throw,{V,x2}}, {'div',{1,0}}, {value,{V,x4}}),
    {{caught,{error,badarith}},
     undefined,
     undefined,
     finalized} =
	nested_catch_1({{value,{V,x1}},void,{V,x1}},
		       {throw,{V,x2}}, {'div',{1,0}}, {'add',{0,b}}),
    %%
    {{caught,{error,{try_clause,{V,x1}}}},
     {V,x3},
     {V,x4},
     finalized} =
	nested_catch_1({{value,{V,x1}},void,try_clause},
		       void, {value,{V,x3}}, {value,{V,x4}}),
    {{caught,{exit,{V,x3}}},
     undefined,
     {V,x4},
     finalized} =
	nested_catch_1({{value,{V,x1}},void,try_clause},
		       void, {exit,{V,x3}}, {value,{V,x4}}),
    {{caught,{throw,{V,x4}}},
     undefined,
     undefined,
     finalized} =
	nested_catch_1({{value,{V,x1}},void,try_clause},
		       void, {exit,{V,x3}}, {throw,{V,x4}}),
    %%
    {{value,{caught1,{V,x2}}},
     {V,x3},
     {V,x4},
     finalized} =
	nested_catch_1({{error,{V,x1}},error,{V,x1}},
		       {value,{V,x2}}, {value,{V,x3}}, {value,{V,x4}}),
    {{caught,{error,badarith}},
     {V,x3},
     {V,x4},
     finalized} =
	nested_catch_1({{error,{V,x1}},error,{V,x1}},
		       {'add',{1,c}}, {value,{V,x3}}, {value,{V,x4}}),
    {{caught,{error,badarith}},
     undefined,
     {V,x4},
     finalized} =
	nested_catch_1({{error,{V,x1}},error,{V,x1}},
		       {'add',{1,c}}, {'div',{17,0}}, {value,{V,x4}}),
    {{caught,{error,badarg}},
     undefined,
     undefined,
     finalized} =
	nested_catch_1({{error,{V,x1}},error,{V,x1}},
		       {'add',{1,c}}, {'div',{17,0}}, {'abs',V}),
    %%
    {{caught,{error,badarith}},
     {V,x3},
     {V,x4},
     finalized} =
	nested_catch_1({{'add',{2,c}},rethrow,void},
		       void, {value,{V,x3}}, {value,{V,x4}}),
    {{caught,{error,badarg}},
     undefined,
     {V,x4},
     finalized} =
	nested_catch_1({{'add',{2,c}},rethrow,void},
		       void, {'abs',V}, {value,{V,x4}}),
    {{caught,{error,function_clause}},
     undefined,
     undefined,
     finalized} =
	nested_catch_1({{'add',{2,c}},rethrow,void},
		       void, {'abs',V}, function_clause),
    ok.

nested_catch_1({X1,C1,V1},
	    X2, X3, X4) ->
    erase(nested3),
    erase(nested4),
    erase(nested),
    Throw = make_ref(),
    Try =
	try
            try throw(Throw)
            catch
		Throw ->
                    try 
                        foo(X1) 
	            of
	                V1 -> {value1,foo(X2)}
                    catch
                        C1:V1 -> {caught1,foo(X2)}
	            after
                        put(nested3, foo(X3))
                    end
            after
                put(nested4, foo(X4))
            end
        of
            V -> {value,V}
        catch
            C:D -> {caught,{C,D}}
        after
            put(nested, finalized)
	end,
    {Try,erase(nested3),erase(nested4),erase(nested)}.



nested_after(Conf) when is_list(Conf) ->
    V = [{make_ref(),1.4142136,self()}],
    {value,
	   {V,x3},
	   {value1,{V,x2}},
	   finalized} =
	nested_after_1({{value,{V,x1}},void,{V,x1}},
		       {value,{V,x2}}, {value,{V,x3}}),
    {{caught,{error,{V,x2}}},
	   {V,x3},
	   undefined,
	   finalized} =
	nested_after_1({{value,{V,x1}},void,{V,x1}},
		       {error,{V,x2}}, {value,{V,x3}}),
    {{caught,{exit,{V,x3}}},
	   undefined,
	   undefined,
	   finalized} =
	nested_after_1({{value,{V,x1}},void,{V,x1}},
		       {error,{V,x2}}, {exit,{V,x3}}),
    %%
    {{caught,{error,{try_clause,{V,x1}}}},
	   {V,x3},
	   undefined,
	   finalized} =
	nested_after_1({{value,{V,x1}},void,try_clause},
		       void, {value,{V,x3}}),
    {{caught,{error,badarith}},
	   undefined,
	   undefined,
	   finalized} =
	nested_after_1({{value,{V,x1}},void,try_clause},
		       void, {'div',{17,0}}),
    %%
    {value,
	   {V,x3},
	   {caught1,{V,x2}},
	   finalized} =
	nested_after_1({{throw,{V,x1}},throw,{V,x1}},
		       {value,{V,x2}}, {value,{V,x3}}),
    {{caught,{error,badarith}},
	   {V,x3},
	   undefined,
	   finalized} =
	nested_after_1({{throw,{V,x1}},throw,{V,x1}},
		       {'add',{a,b}}, {value,{V,x3}}),
    {{caught,{error,badarg}},
	   undefined,
	   undefined,
	   finalized} =
	nested_after_1({{throw,{V,x1}},throw,{V,x1}},
		       {'add',{a,b}}, {'abs',V}),
    %%
    {{caught,{throw,{V,x1}}},
	   {V,x3},
	   undefined,
	   finalized} =
	nested_after_1({{throw,{V,x1}},rethrow,void},
		       void, {value,{V,x3}}),
    {{caught,{error,badarith}},
	   undefined,
	   undefined,
	   finalized} =
	nested_after_1({{throw,{V,x1}},rethrow,void},
		       void, {'div',{1,0}}),
    ok.

nested_after_1({X1,C1,V1},
	    X2, X3) ->
    erase(nested3),
    erase(nested4),
    erase(nested),
    Self = self(),
    Try =
	try
            try self()
            after
                After =
                    try 
                        foo(X1) 
	            of
	                V1 -> {value1,foo(X2)}
                    catch
                        C1:V1 -> {caught1,foo(X2)}
	            after
                        put(nested3, foo(X3))
                    end,
                put(nested4, After)
            end
        of
            Self -> value
        catch
            C:D -> {caught,{C,D}}
        after
            put(nested, finalized)
	end,
    {Try,erase(nested3),erase(nested4),erase(nested)}.



nested_horrid(Config) when is_list(Config) ->
    {[true,true],{[true,1.0],1.0}} =
	nested_horrid_1({true,void,void}, 1.0),
    ok.

nested_horrid_1({X1,C1,V1}, X2) ->
    try A1 = [X1,X1],
	B1 = if X1 ->
		     A2 = [X1,X2],
		     B2 = foo(X2),
		     {A2,B2};
		true ->
		     A3 = [X2,X1],
		     B3 = foo(X2),
		     {A3,B3}
	     end,
	{A1,B1}
    catch
	C1:V1 -> caught1
    end.



foo({value,Value}) -> Value;
foo({'div',{A,B}}) ->
    my_div(A, B);
foo({'add',{A,B}}) ->
    my_add(A, B);
foo({'abs',X}) ->
    my_abs(X);
foo({error,Error}) -> 
    erlang:error(Error);
foo({throw,Throw}) ->
    erlang:throw(Throw);
foo({exit,Exit}) ->
    erlang:exit(Exit);
foo({raise,{Class,Reason}}) ->
    erlang:raise(Class, Reason);
foo(Term) when not is_atom(Term) -> Term.
%%foo(Atom) when is_atom(Atom) -> % must not be defined!

my_div(A, B) ->
    A div B.

my_add(A, B) ->
    A + B.

my_abs(X) -> abs(X).


last_call_optimization(Config) when is_list(Config) ->
    error = in_tail(dum),
    StkSize0 = in_tail(0),
    StkSize = in_tail(50000),
    io:format("StkSize0 = ~p", [StkSize0]),
    io:format("StkSize  = ~p", [StkSize]),
    StkSize = StkSize0,
    ok.

in_tail(E) ->
    try erlang:abs(E) of
        T ->
	    A = id([]),
	    B = id([]),
	    C = id([]),
	    id([A,B,C]),
	    do_tail(T)
    catch error:badarg -> error
    end.

do_tail(0) ->
    process_info(self(), stack_size);
do_tail(N) ->
    in_tail(N-1).

bool(Config) when is_list(Config) ->
    ok = do_bool(false, false),
    error = do_bool(false, true),
    error = do_bool(true, false),
    error = do_bool(true, true),
    error = do_bool(true, blurf),
    {'EXIT',_} = (catch do_bool(blurf, false)),
    ok.

%% The following function used to cause a crash in beam_bool.
do_bool(A0, B) ->
    A = not A0,
    try
	id(42),
	if
	    A, not B -> ok
	end
    catch
	_:_ ->
	    error
    end.

andalso_orelse(Config) when is_list(Config) ->
    {2,{a,42}} = andalso_orelse_1(true, {a,42}),
    {b,{b}} = andalso_orelse_1(false, {b}),
    {caught,no_tuple} = andalso_orelse_1(false, no_tuple),

    ok = andalso_orelse_2({type,[a]}),
    also_ok = andalso_orelse_2({type,[]}),
    also_ok = andalso_orelse_2({type,{a}}),
    ok.

andalso_orelse_1(A, B) ->
    {try
	 if
	     A andalso element(1, B) =:= a ->
		 tuple_size(B);
	     true ->
		 element(1, B)
	 end
     catch error:_ ->
	     caught
     end,B}.

andalso_orelse_2({Type,Keyval}) ->
   try
       if is_atom(Type) andalso length(Keyval) > 0 -> ok;
          true -> also_ok
       end
   catch
       _:_ -> fail
   end.

zero() ->
    0.0.

get_in_try(_) ->
    undefined = get_valid_line([a], []),
    ok.

get_valid_line([_|T]=Path, Annotations) ->
    try
        get(Path)
	%% beam_dead used to optimize away an assignment to {y,1}
	%% because it didn't appear to be used.
    catch
        _:not_found ->
            get_valid_line(T, Annotations)
    end.

hockey(_) ->
    {'EXIT',{{badmatch,_},[_|_]}} = (catch hockey()),
    ok.

hockey() ->
    %% beam_jump used to generate a call into the try block.
    %% beam_validator disapproved.
    receive _ -> (b = fun() -> ok end)
    + hockey, +x after 0 -> ok end, try (a = fun() -> ok end) + hockey, +
    y catch _ -> ok end.


-record(state, {foo}).

handle_info(_Config) ->
    do_handle_info({foo}, #state{}),
    ok.

do_handle_info({_}, State) ->
   handle_info_ok(),
   State#state{foo = bar},
   case ok of
   _ ->
     case catch handle_info_ok() of
     ok ->
       {stop, State}
     end
   end;
do_handle_info(_, State) ->
   (catch begin
     handle_info_ok(),
     State#state{foo = bar}
   end),
   case ok of
   _ ->
     case catch handle_info_ok() of
     ok ->
       {stop, State}
     end
   end.

handle_info_ok() -> ok.

'catch_in_catch'(_Config) ->
    process_flag(trap_exit, true),
    Pid = spawn_link(fun() ->
			     catch_in_catch_init(x),
			     exit(good_exit)
		     end),
    receive
	{'EXIT',Pid,good_exit} ->
	    ok;
	Other ->
	    io:format("Unexpected: ~p\n", [Other]),
	    error
    after 32000 ->
	    io:format("No message received\n"),
	    error
    end.

'catch_in_catch_init'(Param) ->
    process_flag(trap_exit, true),
    %% The catches were improperly nested, causing a "No catch found" crash.
    (catch begin
           id(Param),
           (catch exit(bar))
       end
    ),
    ignore.

grab_bag(_Config) ->
    %% Thanks to Martin Bjorklund.
    _ = fun() -> ok end,
    try
	fun() -> ok end
    after
	fun({A, B}) -> A + B end
    end,

    %% Thanks to Tim Rath.
    A = {6},
    try
	io:fwrite("")
    after
	fun () ->
		fun () -> {_} = A end
	end
    end,

    %% Unnecessary catch.
    22 = (catch 22),

    fun() ->
            F = grab_bag_1(any),
            true = is_function(F, 1)
    end(),

    <<>> = grab_bag_2(whatever),

    {'EXIT',_} = (catch grab_bag_3()),

    true = grab_bag_4(),

    ok.

grab_bag_1(V) ->
    %% V will be stored in y0.
    try
        receive
        after 0 ->
                %% y0 will be re-used for the catch tag.
                %% This is safe, because there are no instructions
                %% that can raise an exception.
                catch 22
        end,
        %% beam_validator incorrectly assumed that the make_fun2
        %% instruction could raise an exception and end up at
        %% the catch part of the try.
        fun id/1
    catch
        %% Never reached, because nothing in the try body raises any
        %% exception.
        _:V ->
            ok
    end.

grab_bag_2(V) ->
    try
        %% y0 will be re-used for the catch tag.
        %% This is safe, because there are no instructions
        %% that can raise an exception.
        catch 22,

        %% beam_validator incorrectly assumed that the bs_init_writable
        %% instruction could raise an exception and end up at
        %% the catch part of the try.
        <<0 || [], #{} <- []>>
    catch
        %% Never reached, because nothing in the try body raises any
        %% exception.
        error:_ ->
            V
    end.

grab_bag_3() ->
    try 2 of
        true ->
            <<
              "" || [V0] = door
            >>
    catch
        error:true:V0 ->
            []
            %% The default clause here (which re-throws the exception)
            %% would not return two values as expected.
    end =:= (V0 = 42).

grab_bag_4() ->
    try
        erlang:yield()
    after
        %% beam_jump would do an unsafe sharing of blocks, resulting
        %% in an ambiguous_catch_try_state diagnostic from beam_validator.
        catch <<>> = size(catch ([_ | _] = ok))
    end.


stacktrace(_Config) ->
    V = [make_ref()|self()],
    case ?MODULE:module_info(native) of
        false ->
            {value2,{caught1,badarg,[{erlang,abs,[V],_}|_]}} =
                stacktrace_1({'abs',V}, error, {value,V}),
            {caught2,{error,badarith},[{erlang,'+',[0,a],_},
                                       {?MODULE,my_add,2,_}|_]} =
                stacktrace_1({'div',{1,0}}, error, {'add',{0,a}});
        true ->
            {value2,{caught1,badarg,[{?MODULE,my_abs,1,_}|_]}} =
                stacktrace_1({'abs',V}, error, {value,V}),
            {caught2,{error,badarith},[{?MODULE,my_add,2,_}|_]} =
                stacktrace_1({'div',{1,0}}, error, {'add',{0,a}})
    end,
    {caught2,{error,{try_clause,V}},[{?MODULE,stacktrace_1,3,_}|_]} =
        stacktrace_1({value,V}, error, {value,V}),
    {caught2,{throw,V},[{?MODULE,foo,1,_}|_]} =
        stacktrace_1({value,V}, error, {throw,V}),

    try
        stacktrace_2()
    catch
        error:{badmatch,_}:Stk2 ->
            [{?MODULE,stacktrace_2,0,_},
             {?MODULE,stacktrace,1,_}|_] = Stk2,
            ok
    end,

    try
        stacktrace_3(a, b)
    catch
        error:function_clause:Stk3 ->
            case lists:module_info(native) of
                false ->
                    [{lists,prefix,[a,b],_}|_] = Stk3;
                true ->
                    [{lists,prefix,2,_}|_] = Stk3
            end
    end,

    try
        throw(x)
    catch
        throw:x:_IntentionallyUnused ->
            ok
    end.

stacktrace_1(X, C1, Y) ->
    try try foo(X) of
            C1 -> value1
        catch
            C1:D1:Stk1 ->
                {caught1,D1,Stk1}
        after
            foo(Y)
        end of
        V2 -> {value2,V2}
    catch
        C2:D2:Stk2 ->
            {caught2,{C2,D2},Stk2}
    end.

stacktrace_2() ->
    ok = erlang:process_info(self(), current_function),
    ok.

stacktrace_3(A, B) ->
    {ok,lists:prefix(A, B)}.

nested_stacktrace(_Config) ->
    V = [{make_ref()}|[self()]],
    value1 = nested_stacktrace_1({{value,{V,x1}},void,{V,x1}},
                                 {void,void,void}),
    case ?MODULE:module_info(native) of
        false ->
            {caught1,
             [{erlang,'+',[V,x1],_},{?MODULE,my_add,2,_}|_],
             value2} =
                nested_stacktrace_1({{'add',{V,x1}},error,badarith},
                                    {{value,{V,x2}},void,{V,x2}}),
            {caught1,
             [{erlang,'+',[V,x1],_},{?MODULE,my_add,2,_}|_],
             {caught2,[{erlang,abs,[V],_}|_]}} =
                nested_stacktrace_1({{'add',{V,x1}},error,badarith},
                                    {{'abs',V},error,badarg});
        true ->
            {caught1,
             [{?MODULE,my_add,2,_}|_],
             value2} =
                nested_stacktrace_1({{'add',{V,x1}},error,badarith},
                                    {{value,{V,x2}},void,{V,x2}}),
            {caught1,
             [{?MODULE,my_add,2,_}|_],
             {caught2,[{?MODULE,my_abs,1,_}|_]}} =
                nested_stacktrace_1({{'add',{V,x1}},error,badarith},
                                    {{'abs',V},error,badarg})
    end,
    ok.

nested_stacktrace_1({X1,C1,V1}, {X2,C2,V2}) ->
    try foo(X1) of
        V1 -> value1
    catch
        C1:V1:S1 ->
            T2 = try foo(X2) of
                     V2 -> value2
                 catch
                     C2:V2:S2 ->
                         {caught2,S2}
                 end,
            {caught1,S1,T2}
    end.

raise(_Config) ->
    test_raise(fun() -> exit({exit,tuple}) end),
    test_raise(fun() -> abs(id(x)) end),
    test_raise(fun() -> throw({was,thrown}) end),

    badarg = bad_raise(fun() -> abs(id(x)) end),

    error = stk_used_in_bin_size(<<0:42>>),
    ok.

stk_used_in_bin_size(Bin) ->
    try
        throw(fail)
    catch
        throw:fail:Stk ->
            %% The compiler would crash because the building of the
            %% stacktrack was sunk into each case arm.
            case Bin of
                <<0:Stk>> -> ok;
                _ -> error
            end
    end.

bad_raise(Expr) ->
    try
        Expr()
    catch
        _:E:Stk ->
            erlang:raise(bad_class, E, Stk)
    end.

test_raise(Expr) ->
    test_raise_1(Expr),
    test_raise_2(Expr),
    test_raise_3(Expr),
    test_raise_4(Expr).

test_raise_1(Expr) ->
    erase(exception),
    try
        do_test_raise_1(Expr)
    catch
        C:E:Stk ->
            {C,E,Stk} = erase(exception)
    end.

do_test_raise_1(Expr) ->
    try
        Expr()
    catch
        C:E:Stk ->
            %% Here the stacktrace must be built.
            put(exception, {C,E,Stk}),
            erlang:raise(C, E, Stk)
    end.

test_raise_2(Expr) ->
    erase(exception),
    try
        do_test_raise_2(Expr)
    catch
        C:E:Stk ->
            {C,E} = erase(exception),
            try
                Expr()
            catch
                _:_:S ->
                    [StkTop|_] = S,
                    [StkTop|_] = Stk
            end
    end.

do_test_raise_2(Expr) ->
    try
        Expr()
    catch
        C:E:Stk ->
            %% Here it is possible to replace erlang:raise/3 with
            %% the raw_raise/3 instruction since the stacktrace is
            %% not actually used.
            put(exception, {C,E}),
            erlang:raise(C, E, Stk)
    end.

test_raise_3(Expr) ->
    try
        do_test_raise_3(Expr)
    catch
        exit:{exception,C,E}:Stk ->
            try
                Expr()
            catch
                C:E:S ->
                    [StkTop|_] = S,
                    [StkTop|_] = Stk
            end
    end.

do_test_raise_3(Expr) ->
    try
        Expr()
    catch
        C:E:Stk ->
            %% Here it is possible to replace erlang:raise/3 with
            %% the raw_raise/3 instruction since the stacktrace is
            %% not actually used.
            erlang:raise(exit, {exception,C,E}, Stk)
    end.

test_raise_4(Expr) ->
    try
        do_test_raise_4(Expr)
    catch
        exit:{exception,C,E,StkTerm}:Stk ->
            %% it's not allowed to do the matching directly in the clause head
            true = (Stk =:= StkTerm),
            try
                Expr()
            catch
                C:E:S ->
                    [StkTop|_] = S,
                    [StkTop|_] = Stk
            end
    end.

do_test_raise_4(Expr) ->
    try
        Expr()
    catch
        C:E:Stk ->
            %% Here the stacktrace must be built.
            erlang:raise(exit, {exception,C,E,Stk}, Stk)
    end.

no_return_in_try_block(Config) when is_list(Config) ->
    1.0 = no_return_in_try_block_1(0),
    1.0 = no_return_in_try_block_1(0.0),

    gurka = no_return_in_try_block_1(gurka),
    [] = no_return_in_try_block_1([]),

    ok.

no_return_in_try_block_1(H) ->
    try
        Float = if
                    is_number(H) -> float(H);
                    true -> no_return()
                end,
        Float + 1
    catch
        throw:no_return -> H
    end.

no_return() -> throw(no_return).

expression_export(_Config) ->
    42 = expr_export_1(),
    42 = expr_export_2(),

    42 = expr_export_3(fun() -> bar end),
    beer = expr_export_3(fun() -> pub end),
    {error,failed} = expr_export_3(fun() -> error(failed) end),
    is_42 = expr_export_3(fun() -> 42 end),
    no_good = expr_export_3(fun() -> bad end),

    <<>> = expr_export_4(<<1:32>>),
    <<"abcd">> = expr_export_4(<<2:32,"abcd">>),
    no_match = expr_export_4(<<0:32>>),
    no_match = expr_export_4(<<777:32>>),

    {1,2,3} = expr_export_5(),
    ok.

expr_export_1() ->
    try Bar = 42 of
        _ -> Bar
    after
        ok
    end.

expr_export_2() ->
    try Bar = 42 of
        _ -> Bar
    catch
        _:_ ->
            error
    end.

expr_export_3(F) ->
    try
        Bar = 42,
        F()
    of
        bar -> Bar;
        pub -> beer;
        Bar -> is_42;
        _ -> no_good
    catch
        error:Reason ->
            {error,Reason}
    end.

expr_export_4(Bin) ->
    try
        SzSz = id(32),
        Bin
    of
        <<Sz:SzSz,Tail:(4*Sz-4)/binary>> -> Tail;
        <<_/binary>> -> no_match
    after
        ok
    end.

expr_export_5() ->
    try
        X = 1,
        Z = 3,
        Y = 2
    of
        2 -> {X,Y,Z}
    after
        ok
    end.

%% GH-4953: Type inference in throw optimization could crash in rare
%% circumstances when a thrown type conflicted with one that was matched in
%% a catch clause.
throw_opt_crash(_Config) ->
    try
        throw_opt_crash_1(id(false), {pass, id(b), id(c)}),
        throw_opt_crash_1(id(false), {crash, id(b)}),
        ok
    catch
        throw:{pass, B, C} ->
            {error, gurka, {B, C}};
        throw:{beta, B, C} ->
            {error, gaffel, {B, C}};
        throw:{gamma, B, C} ->
            {error, grammofon, {B, C}}
    end.

throw_opt_crash_1(true, {_, _ ,_}=Term) ->
    throw(Term);
throw_opt_crash_1(true, {_, _}=Term) ->
    throw(Term);
throw_opt_crash_1(false, _Term) ->
    ok.

coverage(Config) ->
    {'EXIT',{{badfun,true},[_|_]}} = (catch coverage_1()),
    ok = coverage_ssa_throw(),
    error = coverage_pre_codegen(),
    {a,[42]} = do_plain_catch_list(42),
    cover_raise(Config),

    ok.

%% Cover some code in beam_trim.
coverage_1() ->
    try
        true
    catch
        law:business ->
            program
    after
        head
    end(0),
    if
        [2 or 1] ->
            true
    end.

%% Cover some code in beam_ssa_throw.
coverage_ssa_throw() ->
    cst_trivial(),
    cst_raw(),
    cst_stacktrace(),
    cst_types(),

    ok.

cst_trivial() ->
    %% never inspects stacktrace
    try
        cst_trivial_1()
    catch
        _C:_R:_S ->
            ok
    end.

cst_trivial_1() -> throw(id(gurka)).

cst_types() ->
    %% type tests
    try
        cst_types_1()
    catch
        throw:Val when is_atom(Val);
                       is_bitstring(Val);
                       is_binary(Val);
                       is_float(Val);
                       is_integer(Val);
                       is_list(Val);
                       is_map(Val);
                       is_number(Val);
                       is_tuple(Val) ->
            ok;
        throw:[_|_]=Cons when hd(Cons) =/= gurka;
                              tl(Cons) =/= gaffel ->
            %% is_nonempty_list, get_hd, get_tl
            ok;
        throw:Tuple when tuple_size(Tuple) < 5 ->
            %% tuple_size
            ok
    end.

cst_types_1() -> throw(id(gurka)).

cst_stacktrace() ->
    %% build_stacktrace
    try
        cst_stacktrace_1()
    catch
        throw:gurka ->
            ok;
        _C:_R:Stack ->
            id(Stack),
            ok
    end.

cst_stacktrace_1() -> throw(id(gurka)).

cst_raw() ->
    %% raw_raise
    try
        cst_raw_1()
    catch
        throw:gurka ->
            ok;
        _C:_R:Stack ->
            erlang:raise(error, dummy, Stack)
    end.

cst_raw_1() -> throw(id(gurka)).

%% Cover some code in beam_ssa_pre_codegen.
coverage_pre_codegen() ->
    try not (catch 22) of
        true ->
            ok
    catch
        _:_ ->
            error
    end.

%% Cover some code in beam_block:alloc_may_pass/1.
do_plain_catch_list(X) ->
    B = [X],
    catch id({a,B}).

cover_raise(Config) ->
    UncertainClass = uncertain_class(Config),
    badarg = erlang:raise(UncertainClass, reason, []),
    BadClass = bad_class(Config),
    badarg = erlang:raise(BadClass, reason, []),
    ok.

uncertain_class(Config) ->
    case Config of
        [never_ever] ->  error;
        _ -> undefined_class
    end.

bad_class(Config) ->
    case Config of
        [never_ever] -> bad_class;
        _ -> also_bad
    end.

%% GH-7356: Funs weren't considered when checking whether an exception could
%% escape the module, erroneously triggering the optimization in some cases.
throw_opt_funs(_Config) ->
    try throw_opt_funs_1(id(a)) of
        _ -> unreachable
    catch
        _:Val -> a = id(Val)                    %Assertion.
    end,

    F = id(fun throw_opt_funs_1/1),

    try F(a) of
        _ -> unreachable
    catch
        _:_:Stack -> true = length(Stack) > 0   %Assertion.
    end,

    ok.

throw_opt_funs_1(a) ->
    throw(a);
throw_opt_funs_1(I) ->
    I.

id(I) -> I.
