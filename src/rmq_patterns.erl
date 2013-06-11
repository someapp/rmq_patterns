-module(rmq_patterns).
-behavivour(application).

-export([start/2, stop/1]).
-export([load_config/0, 
	 unload_config/0,
	 reload_config/0]).

start(_StartType, _Args)->
  load_config(),
  ok.

stop(_State)->
  unload_config(),
  ok.

load_config()->load_config(?MODULE).
load_config(File)->
   application:load(File).

unload_config()-> unload_config(?MODULE).  
unload_config(Name)->
   application:unload(Name).

reload_config()->
   unload_config(),
   load_config().
 
