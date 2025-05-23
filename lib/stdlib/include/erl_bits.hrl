%%
%% %CopyrightBegin%
%%
%% SPDX-License-Identifier: Apache-2.0
%%
%% Copyright Ericsson AB 1999-2025. All Rights Reserved.
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
%% This is an -*- erlang -*- file.
%% Generic compiler options, passed from the erl_compile module.

-type bt_endian():: 'big' | 'little' | 'native'.
-type bt_sign()  :: 'signed' | 'unsigned'.
-type bt_type()  :: 'integer' | 'float' | 'binary' | 'utf8' | 'utf16' | 'utf32'.
-type bt_unit()  :: 1..256.

-record(bittype, {
          type   :: bt_type() | 'undefined',
	  unit   :: bt_unit() | 'undefined',       %% element unit
          sign   :: bt_sign() | 'undefined',
          endian :: bt_endian() | 'undefined'
         }).
