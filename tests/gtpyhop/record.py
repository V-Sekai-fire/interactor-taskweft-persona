import sys, json, copy, importlib
import gtpyhop
rec=[]
orig=gtpyhop.find_plan
def desc(x):
    if isinstance(x,gtpyhop.Multigoal): return {"multigoal":{k:v for k,v in vars(x).items() if k!='__name__' and isinstance(v,dict)}}
    if isinstance(x,tuple): return [desc(i) for i in x]
    return x
def snap(s): return {k:v for k,v in vars(s).items() if isinstance(v,dict)}
def fp(state,todo,*a,**k):
    st=snap(state); td=[desc(t) for t in todo]
    r=orig(state,todo,*a,**k)
    rec.append({"state":st,"order":{k:[str(i) for i in v] for k,v in st.items()},"todo":td,"result":r})
    return r
gtpyhop.find_plan=fp
m=importlib.import_module("gtpyhop.examples."+sys.argv[1])
getattr(m,"main_legacy",getattr(m,"main"))(do_pauses=False)
json.dump(rec,open(sys.argv[2],"w"),default=str,indent=0)
print(sys.argv[1],len(rec))
