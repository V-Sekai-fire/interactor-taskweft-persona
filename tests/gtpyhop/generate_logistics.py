# Copyright (c) 2026 K. S. Ernest (iFire) Lee
# SPDX-License-Identifier: Apache-2.0 OR MIT
# Writes logistics_hgn from GTPyhop's logistics_hgn example (Clear BSD, see LICENSE.txt), reading recorded/logistics_hgn.json.
# Run from the repository root: python3 -I tests/gtpyhop/generate_logistics.py
# Every object is a codebook entry; kind says what it is (0 package, 1 truck, 2 plane, 3 location, 4 airport, 5 city).
# An action body here sets constants, so what GTPyhop's actions read from the state (the truck a package is in)
# is checked in the method graph; GTPyhop iterates Python sets for trucks, planes and airports, and here each
# city has one truck and one airport, so the codebook order picks the same one.
import json,sys,os
sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from blocks_lib import *
CASE="logistics_hgn"; D="tests/gtpyhop/"+CASE+"/"
REC=json.load(open("tests/gtpyhop/recorded/"+CASE+".json"))
b2i=lambda g,c: g.r(g.n("type/boolToInt",{"a":c}))
CODE=["package1","package2","truck1","truck6","plane2","location1","location2","location3","airport1","location10","airport2","city1","city2","none"]
KIND={"package1":0,"package2":0,"truck1":1,"truck6":1,"plane2":2,"location1":3,"location2":3,"location3":3,"airport1":4,"location10":3,"airport2":4,"city1":5,"city2":5,"none":6}
def K(g,i): return g.ptr("/kind/[b]",b=i)
def graphAt():
    g=GB(); o=g.var("o"); l=g.var("l"); a=g.var("a"); ko=g.var("ko"); kl=g.var("kl"); ka=g.var("ka"); ca=g.var("ca"); cl=g.var("cl")
    ltok=g.var("ltok"); utok=g.var("utok"); lpok=g.var("lpok"); upok=g.var("upok"); w=g.var("w"); ba=g.var("ba"); bc=g.var("bc")
    tf=g.var("tf"); t=g.var("t"); pf=g.var("pf"); pl=g.var("pl"); lastpl=g.var("lastpl"); f1=g.var("f1"); a1=g.var("a1"); f2=g.var("f2"); a2=g.var("a2")
    n=g.ptr("/count/blocks"); G=g.get; I=g.I
    atloc=lambda: g.or_(g.eq(G(ka),I(3)),g.eq(G(ka),I(4)))
    lloc=lambda: g.or_(g.eq(G(kl),I(3)),g.eq(G(kl),I(4)))
    cityof=lambda x: g.ptr("/in_city/[b]",b=x)
    def truck(i): return g.branch(g.and_(g.eq(G(tf),I(0)),g.and_(g.eq(K(g,i),I(1)),g.eq(cityof(g.ptr("/truck_at/[b]",b=i)),G(ca)))),g.seq([g.setv(tf,I(1)),g.setv(t,i)]))
    def plane(i): return g.branch(g.eq(K(g,i),I(2)),g.seq([g.setv(lastpl,i),
        g.branch(g.and_(g.eq(G(pf),I(0)),g.eq(cityof(g.ptr("/plane_at/[b]",b=i)),G(ca))),g.seq([g.setv(pf,I(1)),g.setv(pl,i)]))]))
    def apt(flag,out,city): return lambda i: g.branch(g.and_(g.eq(G(flag),I(0)),g.and_(g.eq(K(g,i),I(4)),g.eq(cityof(i),G(city)))),g.seq([g.setv(flag,I(1)),g.setv(out,i)]))
    parts=[g.setv(a,g.ptr("/at/[b]",b=G(o))),g.setv(ko,K(g,G(o))),g.setv(kl,K(g,G(l))),g.setv(ka,K(g,G(a))),
           g.setv(ca,cityof(G(a))),g.setv(cl,cityof(G(l))),
           g.setv(ltok,b2i(g,g.and_(g.eq(G(kl),I(1)),g.eq(G(a),g.ptr("/truck_at/[b]",b=G(l)))))),
           g.setv(utok,b2i(g,g.and_(g.and_(g.eq(G(ka),I(1)),lloc()),g.eq(g.ptr("/truck_at/[b]",b=G(a)),G(l))))),
           g.setv(lpok,b2i(g,g.and_(g.eq(G(kl),I(2)),g.eq(G(a),g.ptr("/plane_at/[b]",b=G(l)))))),
           g.setv(upok,b2i(g,g.and_(g.and_(g.eq(G(ka),I(2)),g.eq(G(kl),I(4))),g.eq(g.ptr("/plane_at/[b]",b=G(a)),G(l))))),
           g.loop_for(I(0),n,truck),g.loop_for(I(0),n,plane),
           g.branch(g.eq(G(pf),I(0)),g.setv(pl,G(lastpl))),
           g.loop_for(I(0),n,apt(f1,a1,ca)),g.loop_for(I(0),n,apt(f2,a2,cl)),
           g.setv(w,b2i(g,g.and_(g.eq(G(ko),I(0)),g.and_(atloc(),g.and_(lloc(),g.and_(g.eq(G(ca),G(cl)),g.eq(G(tf),I(1)))))))),
           g.setv(ba,b2i(g,g.and_(g.eq(G(ko),I(0)),g.and_(g.eq(G(ka),I(4)),g.and_(g.eq(G(kl),I(4)),g.not_(g.eq(G(ca),G(cl)))))))),
           g.setv(bc,b2i(g,g.and_(g.eq(G(ko),I(0)),g.and_(atloc(),g.and_(g.not_(g.eq(G(ca),G(cl))),g.and_(g.eq(G(f1),I(1)),g.eq(G(f2),I(1))))))))]
    # flow keys are strings, so a sequence of more than ten would run "10" before "2": nest in groups of ten
    def nest(ps): return ps[0] if len(ps)==1 else g.seq([g.seq(ps[i:i+10]) if len(ps[i:i+10])>1 else ps[i] for i in range(0,len(ps),10)])
    root(g,nest(parts)); return g.out("at")
def graphMove(kvehicle,kdest_ok):
    g=GB(); x=g.var("x"); l=g.var("l"); ok=g.var("ok"); G=g.get; I=g.I
    cityof=lambda v: g.ptr("/in_city/[b]",b=v)
    vloc=g.ptr("/truck_at/[b]" if kvehicle==1 else "/plane_at/[b]",b=G(x))
    cond=g.and_(g.eq(K(g,G(x)),I(kvehicle)),kdest_ok(g,l))
    if kvehicle==1: cond=g.and_(cond,g.eq(cityof(vloc),cityof(G(l))))
    root(g,g.setv(ok,b2i(g,cond))); return g.out("move")
def anyloc(g,l): return g.or_(g.eq(K(g,g.get(l)),g.I(3)),g.eq(K(g,g.get(l)),g.I(4)))
def airport(g,l): return g.eq(K(g,g.get(l)),g.I(4))
ga=graphAt(); gt=graphMove(1,anyloc); gp=graphMove(2,airport)
O,L=P("o"),P("l")
def alt(name,flag,tasks): return {"name":name,"graph":ga,"check":[eqc("/graph/"+flag,1)],"subtasks":tasks}
methods={
 "at":{"params":["o","l"],"alternatives":[
   {"name":"done","check":[eqc("/at/[o]",L)],"subtasks":[]},
   alt("load-truck","ltok",[["load_truck",O,L]]), alt("unload-truck","utok",[["unload_truck",O,L]]),
   alt("load-plane","lpok",[["load_plane",O,L]]), alt("unload-plane","upok",[["unload_plane",O,L]]),
   alt("move-within-city","w",[["truck_at",P("t"),P("a")],["at",O,P("t")],["truck_at",P("t"),L],["at",O,L]]),
   alt("move-between-airports","ba",[["plane_at",P("pl"),P("a")],["at",O,P("pl")],["plane_at",P("pl"),L],["at",O,L]]),
   alt("move-between-cities","bc",[["at",O,P("a1")],["at",O,P("a2")],["at",O,L]])]},
 "truck_at":{"params":["x","l"],"alternatives":[
   {"name":"done","check":[eqc("/truck_at/[x]",L)],"subtasks":[]},
   {"name":"drive","graph":gt,"check":[eqc("/graph/ok",1)],"subtasks":[["drive_truck",P("x"),L]]}]},
 "plane_at":{"params":["x","l"],"alternatives":[
   {"name":"done","check":[eqc("/plane_at/[x]",L)],"subtasks":[]},
   {"name":"fly","graph":gp,"check":[eqc("/graph/ok",1)],"subtasks":[["fly_plane",P("x"),L]]}]}}
acts={"drive_truck":{"params":tp("t","l"),"body":[setp("/truck_at/[t]",P("l"))]},
      "load_truck":{"params":tp("o","t"),"body":[setp("/at/[o]",P("t"))]},
      "unload_truck":{"params":tp("o","l"),"body":[setp("/at/[o]",P("l"))]},
      "fly_plane":{"params":tp("p","a"),"body":[setp("/plane_at/[p]",P("a"))]},
      "load_plane":{"params":tp("o","p"),"body":[setp("/at/[o]",P("p"))]},
      "unload_plane":{"params":tp("o","a"),"body":[setp("/at/[o]",P("a"))]}}
VARS=["at","truck_at","plane_at","in_city","kind","count"]
dom={"@context":CTX,"@type":"domain:Definition","name":CASE,"source":"GTPyhop examples/"+CASE,"version":"0.1.0",
 "description":"GTPyhop's logistics_hgn. Every object is a codebook entry and kind says what it is (0 package, 1 truck, 2 plane, 3 location, 4 airport, 5 city). Its unigoal methods on at, truck_at and plane_at are the tasks at(o,l), truck_at(t,l), plane_at(p,a), each with an already-true alternative first, then the methods in GTPyhop's declaration order. The check that a truck or plane is where an unload happens, which GTPyhop's unload actions make, is made in the method graph, because an action here only sets constants. Each city has one truck and one airport, so the codebook order picks the one GTPyhop's set iteration finds.",
 "variables":[{"name":n,"type":"int","init":{}} for n in VARS],"actions":acts,"methods":methods}
os.makedirs(D,exist_ok=True)
json.dump(dom,open(D+"domain.jsonld","w"),indent=1); open(D+"domain.jsonld","a").write("\n")
step=lambda a: a[0]+"("+",".join(a[1:])+")"
NAMES=["two-packages-in-a-city","to-another-city","already-there"]
for i,name in enumerate(NAMES):
    r=REC[i]; st=r["state"]
    # a graph reads every codebook entry, so each map holds one for every entry; "none" is a codebook entry of its own (kind 6)
    full=lambda m: {**{c:"none" for c in CODE},**m}
    p={"@context":CTX,"@type":"domain:Problem","name":CASE+"_"+name.replace("-","_"),"domain":CASE,"version":"0.1.0","codebook":CODE,
       "variables":[{"name":"at","type":"int","init":full(st["at"])},{"name":"truck_at","type":"int","init":full(st["truck_at"])},
                    {"name":"plane_at","type":"int","init":full(st["plane_at"])},{"name":"in_city","type":"int","init":full({**st["in_city"],"city1":"city1","city2":"city2"})},
                    {"name":"kind","type":"int","init":KIND},{"name":"count","type":"int","init":{"blocks":len(CODE)}}],
       "capabilities":{"entities":{},"graph":{"edges":[]}},"todo_list":r["todo"]}
    json.dump(p,open(D+name+".problem.jsonld","w"),indent=1); open(D+name+".problem.jsonld","a").write("\n")
    open(D+name+".expect","w").write("\n".join(step(a) for a in r["result"])+("\n" if r["result"] else ""))
open(D+"cases","w").write("\n".join(NAMES)+"\n")
