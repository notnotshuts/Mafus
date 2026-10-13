'use client';
import {createContext,useCallback,useContext,useEffect,useRef,useState,type ReactNode} from 'react';
import {RELEASE_API,validRelease,type Release} from '@/lib/releases';
type ReleaseState={release:Release|null;loading:boolean;stale:boolean;error:boolean;refresh:()=>void};
const Context=createContext<ReleaseState|null>(null);
const CACHE_KEY='mafus-premium-release';
export function ReleaseProvider({children}:{children:ReactNode}){
  const [release,setRelease]=useState<Release|null>(null);
  const [loading,setLoading]=useState(true);
  const [stale,setStale]=useState(false);
  const [error,setError]=useState(false);
  const controller=useRef<AbortController|null>(null);
  const current=useRef<Release|null>(null);
  const lastRequest=useRef(0);
  const refresh=useCallback(async()=>{
    controller.current?.abort();
    const abort=new AbortController();controller.current=abort;
    const timeout=setTimeout(()=>abort.abort(),8000);
    lastRequest.current=Date.now();setLoading(true);setError(false);
    try{
      const response=await fetch(RELEASE_API,{headers:{Accept:'application/vnd.github+json'},signal:abort.signal,cache:'no-cache'});
      if(!response.ok)throw new Error('Release unavailable');
      const value:unknown=await response.json();
      if(!validRelease(value))throw new Error('Invalid release');
      current.current=value;setRelease(value);setStale(false);
      try{localStorage.setItem(CACHE_KEY,JSON.stringify(value));}catch{}
    }catch{
      // A superseded request must not overwrite a newer result.
      if(controller.current!==abort)return;
      setError(true);setStale(Boolean(current.current));
    }finally{clearTimeout(timeout);if(controller.current===abort)setLoading(false);}
  },[]);
  useEffect(()=>{
    try{const cached:unknown=JSON.parse(localStorage.getItem(CACHE_KEY)??'null');if(validRelease(cached)){current.current=cached;setRelease(cached);setStale(true);}}catch{}
    void refresh();
    const visible=()=>{if(document.visibilityState==='visible' && Date.now()-lastRequest.current>5*60*1000)void refresh();};
    const timer=setInterval(visible,5*60*1000);document.addEventListener('visibilitychange',visible);
    return()=>{controller.current?.abort();controller.current=null;clearInterval(timer);document.removeEventListener('visibilitychange',visible);};
  },[refresh]);
  return <Context.Provider value={{release,loading,stale,error,refresh}}>{children}</Context.Provider>;
}
export function useRelease(){const value=useContext(Context);if(!value)throw new Error('ReleaseProvider missing');return value;}
