// Reuse the established preset parser, input conversions and display pipeline.
#define LDB_FACTORY_REVIEW_TOOL 1
#include "GuideExamples.mm"
#undef main
#include <chrono>
int main(int argc,char** argv) {
 if(argc!=8){fprintf(stderr,"usage: tool old-library new-library repo old-preset new-preset source output-prefix\n");return 1;}
 @autoreleasepool {
  id<MTLDevice> device=MTLCreateSystemDefaultDevice();if(!device)return 2;
  id<MTLCommandQueue> queue=[device newCommandQueue];
  LDBOpticsEngine oldEngine(device,[NSURL fileURLWithPath:@(argv[1])]);
  LDBOpticsEngine newEngine(device,[NSURL fileURLWithPath:@(argv[2])]);
  if(!oldEngine.valid()||!newEngine.valid())return 3;
  fs::path root=argv[3];std::string key=argv[6],prefix=argv[7];
  uint32_t w=960;
  if(const char* requested=getenv("LDB_REVIEW_WIDTH")) {
   char* end=nullptr;unsigned long value=strtoul(requested,&end,10);
   if(!end||*end||value<64||value>8192){fprintf(stderr,"Invalid LDB_REVIEW_WIDTH\n");return 1;}
   w=uint32_t(value);
  }
  uint32_t h=key.rfind("milano",0)!=0?uint32_t(w*9/16):uint32_t(lround(w*455.0/960.0));
  std::vector<simd_float4> source;
  CubeLUT lut;
  if(key=="iso")source=loadRec709Gamma24Chart((root/"inputs/redistributable/ISO_12233-reschart.tif").c_str(),w,h);
  else if(key=="hdr")source=makeHDRSources(w,h);
  else if(key=="optical")source=loadRec709Gamma24Chart((root/"inputs/redistributable/LDB-Synthetic-Optical-Chart.png").c_str(),w,h);
  else if(key=="milano1"||key=="milano2"||key=="milano3") {
   const char* filename=key=="milano1"?"iphone_milano_dwg_1.tif":key=="milano2"?"iphone_milano2___dwg.tif":"iphone_milano3_dwg.tif";
   uint32_t sw=0,sh=0;auto input=loadEncodedTIFF((root/"inputs/redistributable"/filename).c_str(),sw,sh);
   if(input.empty()||sw==0||sh==0)return 4;
   source=resizePixels(convertEncoding(input,LDBWorkingColorSpaceDaVinciIntermediate,false),sw,sh,w,h);
   if(!lut.load((root/"inputs/redistributable/Resolve-DWG-Intermediate-to-Rec709-Gamma24-Guide.cube").c_str()))return 4;
  } else return 4;
  if(source.size()!=size_t(w)*h)return 4;
  if(getenv("LDB_REVIEW_GUIDE_DEPTH"))source=withGuideDepth(source,w,h);
  auto oldPreset=loadPreset(argv[4],w,h),newPreset=loadPreset(argv[5],w,h);
  #if defined(LDB_RESOLUTION_RELATIVE_CANDIDATE) || defined(LDB_ENABLE_FRAME_RELATIVE)
  if(getenv("LDB_REVIEW_BASELINE_FIXED"))oldPreset.processingFlags|=(1u<<30);
#endif
  int benchmarkFrames=32,benchmarkRuns=3;
  if(const char* n=getenv("LDB_REVIEW_BENCHMARK_FRAMES"))benchmarkFrames=atoi(n);
  if(const char* n=getenv("LDB_REVIEW_BENCHMARK_RUNS"))benchmarkRuns=atoi(n);
  if(benchmarkFrames<1||benchmarkFrames>64||benchmarkRuns<1||benchmarkRuns>3)return 1;
  // Exact authored baseline is deliberately preserved, including legacy values.
  // Host range behavior must be checked separately; this is engine/recipe evidence.
  std::vector<simd_float4> before,after;
  const bool standalone=getenv("LDB_REVIEW_STANDALONE")!=nullptr;
  @autoreleasepool { before=standalone?render(newEngine,device,queue,source,w,h,newPreset):render(oldEngine,device,queue,source,w,h,oldPreset); }
  const bool singleRender=getenv("LDB_REVIEW_SINGLE_RENDER")!=nullptr;
  if(!singleRender&&!standalone) { @autoreleasepool { after=render(newEngine,device,queue,source,w,h,newPreset); } }
  else after=before;
  double mae=0,maxError=0;size_t bad=0;
  for(size_t i=0;i<before.size();++i)for(int c=0;c<4;++c){if(!std::isfinite(before[i][c])||!std::isfinite(after[i][c]))++bad;maxError=std::max(maxError,fabs(double(before[i][c])-after[i][c]));if(c<3)mae+=fabs(double(before[i][c])-after[i][c]);}
  if(bad){fprintf(stderr,"Nonfinite components: %zu\n",bad);return 5;}
  auto display=[&](const auto& pixels){return key.rfind("milano",0)!=0?guideRec709Gamma24FromAP1(pixels):guideMilanoDisplayFromAP1(pixels,lut);};
  if(getenv("LDB_REVIEW_SOURCE_ONLY"))return writePNG(prefix+"-source.png",display(source),w,h)?0:6;
  if(standalone) { if(!writePNG(prefix+"-render.png",display(after),w,h))return 6; }
  else if(!writePNG(prefix+"-before.png",display(before),w,h)||!writePNG(prefix+"-after.png",display(after),w,h))return 6;
  if(getenv("LDB_REVIEW_RENDER_ONLY")) {
   std::ofstream audit(prefix+"-render-audit.json");
   audit<<"{\"width\":"<<w<<",\"height\":"<<h<<",\"nonfinite\":0,\"benchmark_performed\":false}\n";
   return audit?0:7;
  }
#if defined(LDB_FINAL_FRAMING_EXPERIMENT) || defined(LDB_ENABLE_FINAL_FRAMING)
  if(getenv("LDB_REVIEW_CACHE_AUDIT")) {
    double maxError=0;int checked=0;
    for(int state=0;state<6;++state) {
      auto test=newPreset;auto input=source;
      if(state==1)test.opticalCenter.x+=.02f;
      if(state==2)test.finalFramingZoom=90;
      if(state==3){test.finalFramingMode=0;test.finalFramingZoom=125;}
      if(state==5)for(auto& pixel:input){pixel.x*=.5f;pixel.y*=.5f;pixel.z*=.5f;}
      for(int repeat=0;repeat<2;++repeat) {@autoreleasepool {
        auto expected=render(oldEngine,device,queue,input,w,h,test);
        auto actual=render(newEngine,device,queue,input,w,h,test);
        for(size_t i=0;i<actual.size();++i)for(int c=0;c<4;++c){
          if(!std::isfinite(actual[i][c]))return 5;
          maxError=std::max(maxError,fabs(double(actual[i][c])-expected[i][c]));
        }
        ++checked;
      }}
    }
    std::ofstream audit(prefix+"-cache-audit.json");
    audit<<"{\"checks\":"<<checked<<",\"max_error\":"<<maxError<<",\"nonfinite\":0}\n";
    return maxError==0?0:8;
  }
#endif
  NSUInteger bytes=source.size()*sizeof(simd_float4);
  id<MTLBuffer> src=[device newBufferWithBytes:source.data() length:bytes options:MTLResourceStorageModeShared];
  id<MTLBuffer> dst=[device newBufferWithLength:bytes options:MTLResourceStorageModeShared];
  auto measure=[&](LDBOpticsEngine& engine,const LDBOpticsParameters& p){
   double gpu=0,wall=0;const int frames=benchmarkFrames;
   for(int i=-4;i<frames;++i){@autoreleasepool { auto start=std::chrono::steady_clock::now();id<MTLCommandBuffer> cb=[queue commandBuffer];engine.encode(cb,src,dst,w,h,p);[cb commit];[cb waitUntilCompleted];if(cb.status!=MTLCommandBufferStatusCompleted)throw std::runtime_error("Benchmark failed");
    if(i>=0){gpu+=(cb.GPUEndTime-cb.GPUStartTime)*1000;wall+=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();}}}
   return std::pair<double,double>{gpu/frames,wall/frames};};
  if(standalone) {
   std::ofstream metrics(prefix+"-metrics.json");metrics<<"{\"width\":"<<w<<",\"height\":"<<h<<",\"nonfinite\":0,\"standalone\":true,\"frames\":"<<benchmarkFrames<<",\"runs\":[";
   for(int run=0;run<benchmarkRuns;++run){auto value=measure(newEngine,newPreset);if(run)metrics<<",";metrics<<"{\"gpu\":"<<value.first<<",\"wall\":"<<value.second<<"}";}
   metrics<<"]}\n";return metrics?0:7;
  }
  std::ofstream metrics(prefix+"-metrics.json");metrics<<"{\"width\":"<<w<<",\"height\":"<<h<<",\"nonfinite\":0,\"mae\":"<<mae/(source.size()*3)<<",\"max_error\":"<<maxError<<",\"frames\":"<<benchmarkFrames<<",\"runs\":[";
  for(int run=0;run<benchmarkRuns;++run){std::pair<double,double> a,b;if(run%2){b=measure(newEngine,newPreset);a=measure(oldEngine,oldPreset);}else{a=measure(oldEngine,oldPreset);b=measure(newEngine,newPreset);}if(run)metrics<<",";metrics<<"{\"old_gpu\":"<<a.first<<",\"new_gpu\":"<<b.first<<",\"old_wall\":"<<a.second<<",\"new_wall\":"<<b.second<<"}";}
  metrics<<"]}\n";if(!metrics)return 7;
  printf("PASS: %s / %s, finite renders and bounded paired timing runs\n",argv[5],argv[6]);
 }
 return 0;
}
