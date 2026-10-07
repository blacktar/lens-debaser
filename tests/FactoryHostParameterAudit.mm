#define LDB_FACTORY_REVIEW_TOOL 1
#include "GuideExamples.mm"
#undef main
int main(int argc,char**argv){
 if(argc!=3 && argc!=4)return 1;
 auto script=loadPreset(argv[1],960,540),host=loadPreset(argv[2],960,540);
 // Host-specific fixed choices are selected independently of optical presets.
 host.depthChannel=0;
 host.workingColorSpace=2;
 if(argc==4){std::ofstream out(argv[3],std::ios::binary);out.write(reinterpret_cast<const char*>(&host),sizeof(host));if(!out)return 2;}
 printf("script aperture amount %.6g radius %.6g drift %.6g blend %.6g look %.6g capture %.6g\n",script.apertureResponse,script.apertureRadius,script.opticalDriftAmount,script.effectBlend,script.lookInfluence,script.captureInfluence);
 printf("host   aperture amount %.6g radius %.6g drift %.6g blend %.6g look %.6g capture %.6g\n",host.apertureResponse,host.apertureRadius,host.opticalDriftAmount,host.effectBlend,host.lookInfluence,host.captureInfluence);
 const auto*a=(const unsigned char*)&script;const auto*b=(const unsigned char*)&host;
 for(size_t i=0;i<sizeof(script);i+=4)if(memcmp(a+i,b+i,4)){float x,y;memcpy(&x,a+i,4);memcpy(&y,b+i,4);printf("different ABI slot %zu: script %.8g host %.8g\n",i,x,y);}
 return 0;
}
