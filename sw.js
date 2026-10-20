/* Service worker mínimo: siempre prueba primero la red (así nunca queda una versión vieja) y usa la copia guardada solo si no hay conexión. No toca pedidos a Supabase. */
const V="v1";
self.addEventListener("install",()=>self.skipWaiting());
self.addEventListener("activate",e=>e.waitUntil(self.clients.claim()));
self.addEventListener("fetch",e=>{
  const r=e.request;
  if(r.method!=="GET"||new URL(r.url).origin!==location.origin)return;
  e.respondWith(fetch(r).then(res=>{
    if(res.ok){const c=res.clone();caches.open(V).then(x=>x.put(r,c)).catch(()=>{})}
    return res;
  }).catch(()=>caches.match(r).then(m=>m||caches.match("/ludmi"))));
});
