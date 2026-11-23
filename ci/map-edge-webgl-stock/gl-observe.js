// Document-start observer only. Each original WebGL call still runs. The GL
// driver supplies actual compile/link verdicts. Nothing writes game pixels.
(() => {
  const state={errors:[],errorCount:0,compiled:0,linked:0,maskCompiled:0,maskLinked:0,maskDrawn:0,
    seamCompiled:0,seamLinked:0,seamDrawn:0,canvas:null,contextLost:0};
  window.vcGL=state;
  const add=(kind,text)=>{
    state.errorCount++;
    if(state.errors.length<40)state.errors.push({kind,text:String(text||'').slice(0,1200)});
  };
  window.addEventListener('error',e=>{
    if(e.error||e.message)add('window-error',e.error||e.message);
  });
  window.addEventListener('unhandledrejection',e=>add('unhandled-rejection',e.reason));
  window.addEventListener('webglcontextlost',e=>{if(e.target.id==='canvas')state.contextLost++;},true);
  if (!window.WebGL2RenderingContext)return;
  const p=WebGL2RenderingContext.prototype;
  const gc=HTMLCanvasElement.prototype.getContext;
  HTMLCanvasElement.prototype.getContext=function(type,...args){
    const gl=gc.call(this,type,...args);
    if(this.id==='canvas'&&gl&&type==='webgl2'){
      state.canvas={id:this.id,version:gl.getParameter(gl.VERSION),glsl:gl.getParameter(gl.SHADING_LANGUAGE_VERSION),
        renderer:gl.getParameter(gl.RENDERER)};
      const info=gl.getExtension('WEBGL_debug_renderer_info');
      if(info)state.canvas.unmaskedRenderer=gl.getParameter(info.UNMASKED_RENDERER_WEBGL);
    }
    return gl;
  };
  const actual=g=>g.canvas instanceof HTMLCanvasElement&&g.canvas.id==='canvas';
  const mask=s=>/state_mask/.test(s);
  const seam=s=>/join_rounding_guard/.test(s);
  const active=new WeakMap(), inspected=new WeakMap();
  const c=p.compileShader;
  p.compileShader=function(shader){
    c.call(this,shader);
    if(!actual(this))return;
    state.compiled++;
    const src=this.getShaderSource(shader)||'', m=mask(src), s=seam(src);
    if(!this.getShaderParameter(shader,this.COMPILE_STATUS)){
      add('compile',this.getShaderInfoLog(shader));return;
    }
    if(m)state.maskCompiled++;
    if(s)state.seamCompiled++;
  };
  const l=p.linkProgram;
  p.linkProgram=function(program){
    l.call(this,program);
    if(!actual(this))return;
    state.linked++;
    let shaders=this.getAttachedShaders(program)||[];
    const src=shaders.map(s=>this.getShaderSource(s)||'').join('\n');
    const status=this.getProgramParameter(program,this.LINK_STATUS);
    if(!status){inspected.delete(program);add('link',this.getProgramInfoLog(program));return;}
    const m=mask(src), s=seam(src);
    inspected.set(program,{m,s});
    if(m)state.maskLinked++;
    if(s)state.seamLinked++;
  };
  const u=p.useProgram;
  p.useProgram=function(program){
    const result=u.call(this,program);
    if(actual(this))active.set(this,program);
    return result;
  };
  for(const k of ['drawArrays','drawElements','drawRangeElements','drawArraysInstanced','drawElementsInstanced']){
    const orig=p[k];
    p[k]=function(...args){
      const result=orig.apply(this,args);
      if(actual(this)){
        const tag=inspected.get(active.get(this));
        if(tag?.m)state.maskDrawn++;
        if(tag?.s)state.seamDrawn++;
      }
      return result;
    };
  }
})();
