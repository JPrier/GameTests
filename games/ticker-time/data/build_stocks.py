import duckdb, csv, json, re, datetime as dt
want = """AAPL MSFT AMZN GOOGL META NVDA TSLA NFLX AMD INTC IBM ORCL CSCO ADBE CRM QCOM TXN MU HPQ DELL EBAY PYPL UBER ABNB BKNG DIS KO PEP MCD SBUX NKE WMT TGT COST HD LOW BBY JPM BAC C WFC GS MS AXP V MA BRK-B JNJ PFE MRK LLY ABBV BMY AMGN GILD MRNA UNH CVS XOM CVX COP OXY BA LMT RTX GE CAT DE MMM HON UPS FDX F GM T VZ CMCSA CHTR PG CL KMB MO PM HSY GIS MDLZ KHC EL MAR HLT DAL UAL LUV CCL RCL NCLH WBD EA TTWO AVGO ADP ACN NOW INTU AMAT LRCX KLAC ISRG TMO MDT ABT SYK NEE DUK AMT SPG BLK SCHW COF CME SPGI MCO LULU ROST TJX ORLY AZO YUM CMG DPZ DRI HAS PANW CRWD FTNT ANET SNPS CDNS PLTR COIN EXPE HPE GRMN TSCO KR DG DLTR ULTA HAL SLB DVN NEM FCX DOW DD FOXA NWSA LYV WYNN MGM LVS CZR KDP STZ TAP CLX CHD MKC SJM CPB HRL TSN CAG""".split()
names={}
for r in csv.DictReader(open('sp.csv')): names[r['Symbol'].replace('.','-')]=r['Security']
def clean(n):
    n=re.sub(r'\s*\(Class [A-Z]\)','',n)
    m=re.match(r'(.*) \(The\)$',n)
    if m: n='The '+m.group(1)
    n=re.sub(r',? Inc\.$','',n)
    return n.strip()
override={'GOOGL':'Alphabet (Google)','META':'Meta Platforms (Facebook)','BRK-B':'Berkshire Hathaway','WMT':'Walmart','HD':'Home Depot','PG':'Procter & Gamble','JNJ':'Johnson & Johnson','KO':'Coca-Cola','DIS':'Walt Disney','MCD':"McDonald's",'GE':'General Electric','BA':'Boeing','EA':'Electronic Arts','CZR':'Caesars Entertainment','TAP':'Molson Coors','CPB':"Campbell's",'CAG':'Conagra Brands','LLY':'Eli Lilly','HON':'Honeywell','ORCL':'Oracle','TGT':'Target','CVX':'Chevron','SYK':'Stryker','SCHW':'Charles Schwab','MRK':'Merck','HSY':'Hershey','EL':'Estée Lauder','SJM':'J.M. Smucker','UAL':'United Airlines','NCLH':'Norwegian Cruise Line','RCL':'Royal Caribbean','CCL':'Carnival','DE':'John Deere','F':'Ford','UPS':'UPS','ADP':'ADP','TJX':'TJX (T.J. Maxx)','FCX':'Freeport-McMoRan','MCO':"Moody's",'MKC':'McCormick','HLT':'Hilton','MAR':'Marriott','ISRG':'Intuitive Surgical','TMO':'Thermo Fisher','SLB':'SLB (Schlumberger)'}
c=duckdb.connect()
c.sql("create table p as select date::date d, ticker t, close from 'prices.parquet' where ticker in (%s) and close>0"%','.join(repr(x) for x in want))
# week key: Friday ending the week
c.sql("create table w as select t, d + (4 - (dayofweek(d)+6)%7)::int as fri, arg_max(close,d) as close from p group by t, fri")
fris=[r[0] for r in c.sql("select distinct fri from w order by 1").fetchall()]
idx={f:i for i,f in enumerate(fris)}
out=[]; flagged=[]
for t in want:
    rows=c.sql(f"select fri, close from w where t='{t}' order by fri").fetchall()
    s=idx[rows[0][0]]; vals=[None]*(idx[rows[-1][0]]-s+1)
    for f,v in rows: vals[idx[f]-s]=v
    for i in range(len(vals)):  # forward-fill holiday gaps
        if vals[i] is None: vals[i]=vals[i-1]
    bad=[]
    for i in range(1,len(vals)):
        r=vals[i]/vals[i-1]
        if r>1.8 or r<0.45: bad.append((str(fris[s+i]),round(r,2)))
    if bad: flagged.append((t,bad))
    badw={'MO':('2008-03-21','2008-04-11'),'KDP':('2018-07-06','2018-07-20')}
    b=[i for i in range(len(vals)) if t in badw and badw[t][0]<=str(fris[s+i])<=badw[t][1]]
    def f4(v): return float('%.4g'%v)
    out.append({'t':t.replace('-','.'),'n':override.get(t,clean(names.get(t,t))),'s':s,'c':[f4(v) for v in vals],'b':b})
for f in flagged: print('FLAG',f)
data={'w0':str(fris[0]),'nw':len(fris),'stocks':out}
json.dump(data,open('stocks.json','w'),separators=(',',':'))
import os; print(len(out),'stocks',len(fris),'weeks',fris[0],fris[-1],os.path.getsize('stocks.json'))
print([ (o['t'],o['n']) for o in out][:200])
