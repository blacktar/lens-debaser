#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include "LDBOpticsEngine.h"
#include "LDBProjectionCandidateParameters.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <vector>
static void require(bool ok,const char* message){if(!ok){std::fprintf(stderr,"FAIL: %s\n",message);std::exit(1);}}
static void hostChecks(){
 auto p=LDBNeutralOpticsParameters(64,48);
 LDBSetProjectionCandidate(p,2,45,55,1);
 require(p.reservedV4_4==3 && std::abs(p.reservedV4_3-.45f)<1e-6f && p.reservedV4_7==.55f,"Named controls map to the established experiment");
 LDBSetProjectionCandidate(p,1,200,100,2);
 require(p.reservedV4_3==1 && p.reservedV4_5==89 && p.reservedV4_7==1,"Public range clamps");
 LDBSetProjectionCandidate(p,1,-1,-1,0);require(!LDBProjectionCandidateActive(p),"Negative values disable projection");
 LDBSetProjectionCandidate(p,0,100,89,1);require(!LDBProjectionCandidateActive(p),"Off disables projection");
 LDBSetProjectionCandidate(p,1,100,0,1);require(!LDBProjectionCandidateActive(p),"Zero angle is identity");
 LDBSetProjectionCandidate(p,1,0,55,1);require(!LDBProjectionCandidateActive(p),"Zero amount is identity");
 LDBSetProjectionCandidate(p,2,std::numeric_limits<double>::quiet_NaN(),55,1);require(!LDBProjectionCandidateActive(p),"Invalid amount is neutral");
 LDBSetProjectionCandidate(p,1,45,std::numeric_limits<double>::infinity(),1);require(!LDBProjectionCandidateActive(p),"Invalid angle is neutral");
 std::puts("PASS: named control mapping, ranges, Off, zero Amount/Angle and invalid inputs");
}
static std::vector<simd_float4> render(LDBOpticsEngine& engine,id<MTLDevice> device,id<MTLCommandQueue> queue,const std::vector<simd_float4>& image,const LDBOpticsParameters& p){
 NSUInteger bytes=image.size()*sizeof(simd_float4);
 auto src=[device newBufferWithBytes:image.data() length:bytes options:MTLResourceStorageModeShared];
 auto dst=[device newBufferWithLength:bytes options:MTLResourceStorageModeShared];
 auto command=[queue commandBuffer];engine.encode(command,src,dst,64,48,p);[command commit];[command waitUntilCompleted];
 require(command.status==MTLCommandBufferStatusCompleted,"GPU command completed");
 auto values=static_cast<simd_float4*>(dst.contents);return {values,values+image.size()};
}
int main(int argc,char**argv){
 hostChecks();if(argc==2&&std::strcmp(argv[1],"--host-only")==0)return 0;
 require(argc==3,"usage: candidate-tests baseline.metallib candidate.metallib | --host-only");
 @autoreleasepool{
  auto device=MTLCreateSystemDefaultDevice();require(device!=nil,"Metal device required");auto queue=[device newCommandQueue];
  LDBOpticsEngine base(device,[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]]);
  LDBOpticsEngine candidate(device,[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[2]]]);
  require(base.valid()&&candidate.valid(),"Both libraries load");
  std::vector<simd_float4> image(64*48);
  for(int y=0;y<48;++y)for(int x=0;x<64;++x)image[y*64+x]={float(x)/64,float(y)/48,((x/4+y/4)%2)?1.5f:.03f,1};
  for(int recipe:{0,1}){
   auto p=LDBNeutralOpticsParameters(64,48);
#if defined(LDB_ENABLE_FRAME_RELATIVE)
   p.processingFlags|=(1u<<30); // This test explicitly checks legacy Fixed Pixels parity.
#endif
   if(recipe){p.distortionK1=-.03f;p.lateralCARed=1.8f;p.lateralCABlue=-2.2f;p.cornerSharpnessLoss=.72f;p.fieldCurvature=.48f;}
   auto reference=render(base,device,queue,image,p);
   for(int mode:{0,1,2}){
    auto q=p;LDBSetProjectionCandidate(q,mode==0?0:1,mode==1?0:100,mode==2?0:55,1);
    auto actual=render(candidate,device,queue,image,q);
    require(std::memcmp(reference.data(),actual.data(),reference.size()*sizeof(simd_float4))==0,"Disabled projection preserves baseline bit-for-bit");
   }
  }
  std::puts("PASS: Off, zero Amount and zero Angle preserve released neutral and optical output bit-for-bit");
  auto neutral=LDBNeutralOpticsParameters(64,48);auto unchanged=render(base,device,queue,image,neutral);
  for(int model:{1,2}){
   auto p=neutral;LDBSetProjectionCandidate(p,model,45,55,1);auto actual=render(candidate,device,queue,image,p);
   require(std::memcmp(unchanged.data(),actual.data(),actual.size()*sizeof(simd_float4))!=0,"Projection alone activates rendering without distortion workaround");
  }
  std::puts("PASS: both projection models activate independently of distortion");
  int cases=0;
  // Small endpoint validation, including the displaced-axis condition absent
  // from the previous sweep, rather than another visual matrix.
  for(int model:{1,2})for(int framing:{0,1,2})for(int angle:{0,89})for(int center:{0,1}){
   auto p=neutral;p.opticalCenter=center?simd_float2{0,0}:simd_float2{.5f,.5f};
   LDBSetProjectionCandidate(p,model,100,angle,framing);auto actual=render(candidate,device,queue,image,p);
   for(const auto& pixel:actual)for(int c=0;c<4;++c)require(std::isfinite(pixel[c]),"Endpoint/displaced-axis output remains finite");++cases;
  }
  std::printf("PASS: %d small GPU endpoint cases finite, including displaced optical axis\n",cases);
 }
 return 0;
}
