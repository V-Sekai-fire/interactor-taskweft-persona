# Copyright (c) 2026 K. S. Ernest (iFire) Lee
# SPDX-License-Identifier: Apache-2.0 OR MIT
# Writes this directory's domain and problems from GTPyhop's blocks_gtn example (Clear BSD, see ../LICENSE.txt).
# The graphs are generated because a graph in JSON is not readable: is_done is the loop GTPyhop's recursion is,
# and m_moveblocks is two passes over the clear blocks in the order of the problem's codebook.
# Run from the repository root: python3 -I tests/gtpyhop/blocks_gtn/generate.py
import json
D="tests/gtpyhop/blocks_gtn/"
TABLE,HAND,FREE,NOTHING=-1,-2,-3,-4
class GB:
    def __init__(s): s.nodes=[]; s.ops=[]; s.vars=[]
    def var(s,id,t=0,v=0): s.vars.append({"id":id,"type":t,"value":[v]}); return len(s.vars)-1
    def n(s,op,values=None,flows=None,config=None):
        if op not in s.ops: s.ops.append(op)
        d={"declaration":s.ops.index(op)}
        if config: d["configuration"]=config
        if values: d["values"]=values
        if flows: d["flows"]=flows
        s.nodes.append(d); return len(s.nodes)-1
    # values
    def I(s,v): return {"type":0,"value":[v]}
    def r(s,n,sock="value"): return {"node":n,"socket":sock}
    def get(s,i): return s.r(s.n("variable/get",None,None,{"variable":{"value":[i]}}))
    def ptr(s,path,**p): return s.r(s.n("pointer/get",{k:v for k,v in p.items()},None,{"pointer":{"value":[path]},"type":{"value":[0]}}))
    def op(s,o,a,b): return s.r(s.n(o,{"a":a,"b":b}))
    def eq(s,a,b): return s.op("math/eq",a,b)
    def ge(s,a,b): return s.op("math/ge",a,b)
    def and_(s,a,b): return s.op("math/and",a,b)
    def or_(s,a,b): return s.op("math/or",a,b)
    def not_(s,a): return s.r(s.n("math/not",{"a":a}))
    # flows: each returns the entry node
    def setv(s,i,val): return s.n("variable/set",{str(i):val},None,{"variables":{"value":[i]}})
    def seq(s,parts):
        q=s.n("flow/sequence")
        s.nodes[q]["flows"]={str(k):{"node":p,"socket":"in"} for k,p in enumerate(parts)}
        return q
    def branch(s,cond,t=None,f=None):
        b=s.n("flow/branch",{"condition":cond}); fl={}
        if t is not None: fl["true"]={"node":t,"socket":"in"}
        if f is not None: fl["false"]={"node":f,"socket":"in"}
        s.nodes[b]["flows"]=fl; return b
    def loop_for(s,start,end,body_fn):
        f=s.n("flow/for",{"startIndex":start,"endIndex":end}); body=body_fn(s.r(f,"index"))
        s.nodes[f]["flows"]={"loopBody":{"node":body,"socket":"in"}}; return f
    def loop_while(s,cond,body):
        w=s.n("flow/while",{"condition":cond}); s.nodes[w]["flows"]={"loopBody":{"node":body,"socket":"in"}}; return w
    def isdone(s,tag,start):
        """is_done(b1, state, mgoal), written as the loop GTPyhop's recursion is. Returns (entry, result variable)."""
        cur=s.var(f"cur{tag}"); res=s.var(f"res{tag}",0,1); go=s.var(f"go{tag}",0,1)
        init=s.seq([s.setv(cur,start),s.setv(res,s.I(1)),s.setv(go,s.I(1))])
        gcur=lambda: s.get(cur)
        mism=s.and_(s.not_(s.eq(s.ptr("/goal/[c]",c=gcur()),s.I(FREE))),s.not_(s.eq(s.ptr("/goal/[c]",c=gcur()),s.ptr("/pos/[c]",c=gcur()))))
        onT=s.eq(s.ptr("/pos/[c]",c=gcur()),s.I(TABLE))
        step=s.branch(mism,s.seq([s.setv(res,s.I(0)),s.setv(go,s.I(0))]),
                      s.branch(onT,s.setv(go,s.I(0)),s.setv(cur,s.ptr("/pos/[c]",c=gcur()))))
        cond=s.and_(s.ge(s.get(go),s.I(1)),s.not_(s.eq(gcur(),s.I(TABLE))))
        return s.seq([init,s.loop_while(cond,step)]),res
    def out(s,name):
        return {"types":[{"signature":"int"},{"signature":"bool"}],"variables":s.vars,
                "declarations":[{"op":o} for o in s.ops],"nodes":s.nodes}
def root(g,entry):
    st=g.n("event/onStart",None,{"out":{"node":entry,"socket":"in"}}); return st
# --- graph A: the first clear block that can move to where it need not move again
def graphA():
    g=GB(); found=g.var("found"); x=g.var("x"); dest=g.var("dest")
    n=g.ptr("/count/blocks")
    def body(i):
        d1,r1=g.isdone("1",i)
        goal_i=g.ptr("/goal/[b]",b=i)
        tbl=g.or_(g.eq(goal_i,g.I(FREE)),g.eq(goal_i,g.I(TABLE)))
        to_table=g.seq([g.setv(found,g.I(1)),g.setv(x,i),g.setv(dest,g.I(TABLE))])
        d2,r2=g.isdone("2",g.ptr("/goal/[b]",b=i))
        gi=g.ptr("/goal/[b]",b=i)
        ok=g.and_(g.eq(g.get(r2),g.I(1)),g.ge(g.ptr("/clear/[b]",b=gi),g.I(1)))
        to_block=g.seq([g.setv(found,g.I(1)),g.setv(x,i),g.setv(dest,g.ptr("/goal/[b]",b=i))])
        inner=g.seq([d1,g.branch(g.eq(g.get(r1),g.I(0)),g.branch(tbl,to_table,g.seq([d2,g.branch(ok,to_block)])))])
        return g.branch(g.and_(g.eq(g.get(found),g.I(0)),g.ge(g.ptr("/clear/[b]",b=i),g.I(1))),inner)
    root(g,g.loop_for(g.I(0),n,body)); return g.out("A")
# --- graph B: the first clear block that is waiting and is not on the table
def graphB():
    g=GB(); found=g.var("found"); x=g.var("x")
    n=g.ptr("/count/blocks")
    def body(i):
        d1,r1=g.isdone("1",i)
        cond=g.and_(g.eq(g.get(r1),g.I(0)),g.not_(g.eq(g.ptr("/pos/[b]",b=i),g.I(TABLE))))
        inner=g.seq([d1,g.branch(cond,g.seq([g.setv(found,g.I(1)),g.setv(x,i)]))])
        return g.branch(g.and_(g.eq(g.get(found),g.I(0)),g.ge(g.ptr("/clear/[b]",b=i),g.I(1))),inner)
    root(g,g.loop_for(g.I(0),n,body)); return g.out("B")
# --- graph for take: the block x rests on p, and p is a block, not the table
def graphTake():
    g=GB(); x=g.var("x"); p=g.var("p"); valid=g.var("valid")
    s1=g.setv(p,g.ptr("/pos/[b]",b=g.get(x)))
    s2=g.setv(valid,g.r(g.n("type/boolToInt",{"a":g.ge(g.get(p),g.I(0))})))
    root(g,g.seq([s1,s2])); return g.out("take")
def graphPut(kind):
    g=GB(); y=g.var("y"); ok=g.var("ok")
    cond=g.eq(g.get(y),g.I(TABLE)) if kind=="table" else g.ge(g.get(y),g.I(0))
    root(g,g.setv(ok,g.r(g.n("type/boolToInt",{"a":cond})))); return g.out("put")
P=lambda n:{"param":n}
ge=lambda ptr,v:{"eval":{"type":"math/ge","a":{"type":"pointer/get","pointer":ptr},"b":v}}
eqc=lambda ptr,v:{"eval":{"type":"math/eq","a":{"type":"pointer/get","pointer":ptr},"b":v}}
setp=lambda ptr,v:{"pointer/set":ptr,"value":v}
tp=lambda *names:[{"name":n,"enum":"codebook"} for n in names]
dom={"@context":{"VSEKAI":"https://v-sekai.org/","domain":"VSEKAI:planning/domain/"},"@type":"domain:Definition",
 "name":"blocks_gtn","source":"GTPyhop examples/blocks_gtn","version":"0.1.0",
 "description":"GTPyhop's blocks_gtn. A block is its index in the problem's codebook, in the order GTPyhop's state.clear dictionary lists the blocks, which is the order m_moveblocks visits them. pos is a block, table (-1) or hand (-2); clear is 0 or 1; holding is a block, or nothing (-4); the multigoal is goal/<block>, a block, table, or free (-3) for a block the goal says nothing about.",
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
  "moveblocks":{"params":[],"alternatives":[
    {"name":"to-final-place","graph":graphA(),"check":[ge("/graph/found",1)],"subtasks":[["take",P("x")],["put",P("x"),P("dest")],["moveblocks"]]},
    {"name":"out-of-the-way","graph":graphB(),"check":[ge("/graph/found",1)],"subtasks":[["take",P("x")],["put",P("x"),"table"],["moveblocks"]]},
    {"name":"done","subtasks":[]}]}}}
json.dump(dom,open(D+"domain.jsonld","w"),indent=1); open(D+"domain.jsonld","a").write("\n")
ctx=dom["@context"]
def problem(name,codebook,pos,clear,goal,todo,expect):
    n=len(codebook)
    p={"@context":ctx,"@type":"domain:Problem","name":"blocks_gtn_"+name.replace("-","_"),"domain":"blocks_gtn","version":"0.1.0",
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
problem("goal1a",*S1,{"c":"b","b":"a","a":"table"},[["moveblocks"]],exp1)
problem("goal1b",*S1,{"c":"b","b":"a"},[["moveblocks"]],exp1)
problem("sussman",*SU,{"a":"b","b":"c"},[["moveblocks"]],["unstack(c,a)","putdown(c)","pickup(b)","stack(b,c)","pickup(a)","stack(a,b)"])
