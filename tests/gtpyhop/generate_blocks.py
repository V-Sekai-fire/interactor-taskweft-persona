# Copyright (c) 2026 K. S. Ernest (iFire) Lee
# SPDX-License-Identifier: Apache-2.0 OR MIT
# Writes this directory's domain and problems from GTPyhop's blocks_gtn example (Clear BSD, see ../LICENSE.txt).
# The graphs are generated because a graph in JSON is not readable: is_done is the loop GTPyhop's recursion is,
# and m_moveblocks is two passes over the clear blocks in the order of the problem's codebook.
# Run from the repository root: python3 -I tests/gtpyhop/generate_blocks.py blocks_gtn   (or blocks_htn)
# blocks_gtn names its top task moveblocks (a multigoal method); blocks_htn names it achieve (a task method).
import json,sys,os
sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from blocks_lib import *
CASE=sys.argv[1]; TOP={"blocks_gtn":"moveblocks","blocks_htn":"achieve"}[CASE]
D="tests/gtpyhop/"+CASE+"/"
P=lambda n:{"param":n}
ge=lambda ptr,v:{"eval":{"type":"math/ge","a":{"type":"pointer/get","pointer":ptr},"b":v}}
eqc=lambda ptr,v:{"eval":{"type":"math/eq","a":{"type":"pointer/get","pointer":ptr},"b":v}}
setp=lambda ptr,v:{"pointer/set":ptr,"value":v}
tp=lambda *names:[{"name":n,"enum":"codebook"} for n in names]
dom={"@context":{"VSEKAI":"https://v-sekai.org/","domain":"VSEKAI:planning/domain/"},"@type":"domain:Definition",
 "name":CASE,"source":"GTPyhop examples/"+CASE,"version":"0.1.0",
 "description":"GTPyhop's "+CASE+". A block is its index in the problem's codebook, in the order GTPyhop's state.clear dictionary lists the blocks, which is the order m_moveblocks visits them. pos is a block, table (-1) or hand (-2); clear is 0 or 1; holding is a block, or nothing (-4); the multigoal is goal/<block>, a block, table, or free (-3) for a block the goal says nothing about.",
 "enums":{"place":{"table":TABLE,"hand":HAND,"free":FREE,"nothing":NOTHING}},
 "variables":[{"name":n,"type":"int","init":{}} for n in ["pos","clear","holding","goal","count"]],
 "actions":{
  "pickup":{"params":tp("x"),"body":[eqc("/pos/[x]","table"),ge("/clear/[x]",1),eqc("/holding/hand","nothing"),
            setp("/pos/[x]","hand"),setp("/clear/[x]",0),setp("/holding/hand",P("x"))]},
  "unstack":{"params":tp("b1","b2"),"body":[eqc("/pos/[b1]",P("b2")),ge("/clear/[b1]",1),eqc("/holding/hand","nothing"),
            setp("/pos/[b1]","hand"),setp("/clear/[b1]",0),setp("/holding/hand",P("b1")),setp("/clear/[b2]",1)]},
  "putdown":{"params":tp("b1"),"body":[eqc("/pos/[b1]","hand"),setp("/pos/[b1]","table"),setp("/clear/[b1]",1),setp("/holding/hand","nothing")]},
  "stack":{"params":tp("b1","b2"),"body":[eqc("/pos/[b1]","hand"),ge("/clear/[b2]",1),setp("/pos/[b1]",P("b2")),setp("/clear/[b1]",1),
            setp("/holding/hand","nothing"),setp("/clear/[b2]",0)]}},
 "methods":{
  "take":{"params":["x"],"alternatives":[
    {"name":"pickup","check":[ge("/clear/[x]",1),eqc("/pos/[x]","table")],"subtasks":[["pickup",P("x")]]},
    {"name":"unstack","graph":graphTake(),"check":[ge("/clear/[x]",1),ge("/graph/valid",1)],"subtasks":[["unstack",P("x"),P("p")]]}]},
  "put":{"params":["x","y"],"alternatives":[
    {"name":"putdown","graph":graphPut("table"),"check":[eqc("/holding/hand",P("x")),ge("/graph/ok",1)],"subtasks":[["putdown",P("x")]]},
    {"name":"stack","graph":graphPut("block"),"check":[eqc("/holding/hand",P("x")),ge("/graph/ok",1)],"subtasks":[["stack",P("x"),P("y")]]}]},
  TOP:{"params":[],"alternatives":[
    {"name":"to-final-place","graph":graphA(),"check":[ge("/graph/found",1)],"subtasks":[["take",P("x")],["put",P("x"),P("dest")],[TOP]]},
    {"name":"out-of-the-way","graph":graphB(),"check":[ge("/graph/found",1)],"subtasks":[["take",P("x")],["put",P("x"),"table"],[TOP]]},
    {"name":"done","graph":graphC(),"check":[eqc("/graph/found",0)],"subtasks":[]}]}}}
json.dump(dom,open(D+"domain.jsonld","w"),indent=1); open(D+"domain.jsonld","a").write("\n")
ctx=dom["@context"]
def problem(name,codebook,pos,clear,goal,todo,expect):
    n=len(codebook)
    p={"@context":ctx,"@type":"domain:Problem","name":CASE+"_"+name.replace("-","_"),"domain":CASE,"version":"0.1.0",
       "codebook":codebook,
       "variables":[{"name":"pos","type":"int","init":pos},{"name":"clear","type":"int","init":clear},
                    {"name":"holding","type":"int","init":{"hand":"nothing"}},
                    {"name":"goal","type":"int","init":{b:goal.get(b,"free") for b in codebook}},
                    {"name":"count","type":"int","init":{"blocks":n}}],
       "capabilities":{"entities":{},"graph":{"edges":[]}},"todo_list":todo}
    json.dump(p,open(D+name+".problem.jsonld","w"),indent=1); open(D+name+".problem.jsonld","a").write("\n")
    open(D+name+".expect","w").write("\n".join(expect)+"\n")
S1=(["c","b","a"],{"a":"b","b":"table","c":"table"},{"c":True,"b":False,"a":True})
SU=(["c","a","b"],{"c":"a","a":"table","b":"table"},{"c":True,"a":False,"b":True})
R="REFUSED:unreachable"
problem("pickup-a",*S1,{},[["pickup","a"]],[R])
problem("pickup-b",*S1,{},[["pickup","b"]],[R])
problem("take-b",*S1,{},[["take","b"]],[R])
problem("pickup-c",*S1,{},[["pickup","c"]],["pickup(c)"])
problem("take-a",*S1,{},[["take","a"]],["unstack(a,b)"])
problem("take-c",*S1,{},[["take","c"]],["pickup(c)"])
problem("take-a-put-a-table",*S1,{},[["take","a"],["put","a","table"]],["unstack(a,b)","putdown(a)"])
exp1=["unstack(a,b)","putdown(a)","pickup(b)","stack(b,a)","pickup(c)","stack(c,b)"]
problem("goal1a",*S1,{"c":"b","b":"a","a":"table"},[[TOP]],exp1)
problem("goal1b",*S1,{"c":"b","b":"a"},[[TOP]],exp1)
problem("sussman",*SU,{"a":"b","b":"c"},[[TOP]],["unstack(c,a)","putdown(c)","pickup(b)","stack(b,c)","pickup(a)","stack(a,b)"])
# --- the larger problems of blocks_htn's examples.py (also valid for blocks_gtn: the same states, goals and plans)
# Only the goal's pos part is encoded; GTPyhop's clear and holding goal parts are not read by m_moveblocks.
S2=(["a","c","b","d"],{"a":"c","b":"d","c":"table","d":"table"},{"a":True,"c":False,"b":True,"d":False})
exp2=["unstack(a,c)","putdown(a)","unstack(b,d)","stack(b,c)","pickup(a)","stack(a,d)"]
problem("goal2a",*S2,{"b":"c","a":"d","c":"table","d":"table"},[[TOP]],exp2)
problem("goal2b",*S2,{"b":"c","a":"d"},[[TOP]],exp2)
# run_lazy_lookahead ends in this state, where find_plan answers the empty plan
problem("goal2b-done",["a","c","b","d"],{"a":"d","b":"c","c":"table","d":"table"},{"a":True,"c":False,"b":True,"d":False},{"b":"c","a":"d"},[[TOP]],[])
B3=[str(i) for i in range(1,20)]
P3={1:12,12:13,13:"table",11:10,10:5,5:4,4:14,14:15,15:"table",9:8,8:7,7:6,6:"table",19:18,18:17,17:16,16:3,3:2,2:"table"}
pos3={str(k):(str(v) if v!="table" else v) for k,v in P3.items()}
clear3={str(i):i in (1,11,9,19) for i in range(1,20)}
G3={15:13,13:8,8:9,9:4,4:"table",12:2,2:3,3:16,16:11,11:7,7:6,6:"table"}
goal3={str(k):(str(v) if v!="table" else v) for k,v in G3.items()}
problem("goal3",B3,pos3,clear3,goal3,[[TOP]],['unstack(1,12)', 'putdown(1)', 'unstack(19,18)', 'putdown(19)', 'unstack(18,17)', 'putdown(18)', 'unstack(17,16)', 'putdown(17)', 'unstack(9,8)', 'putdown(9)', 'unstack(8,7)', 'putdown(8)', 'unstack(11,10)', 'stack(11,7)', 'unstack(10,5)', 'putdown(10)', 'unstack(5,4)', 'putdown(5)', 'unstack(4,14)', 'putdown(4)', 'pickup(9)', 'stack(9,4)', 'pickup(8)', 'stack(8,9)', 'unstack(14,15)', 'putdown(14)', 'unstack(16,3)', 'stack(16,11)', 'unstack(3,2)', 'stack(3,16)', 'pickup(2)', 'stack(2,3)', 'unstack(12,13)', 'stack(12,2)', 'pickup(13)', 'stack(13,8)', 'pickup(15)', 'stack(15,13)'])
