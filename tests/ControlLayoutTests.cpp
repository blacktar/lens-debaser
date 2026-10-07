#include "LDBControlLayout.h"
#include <cassert>
#include <iostream>
#include <map>
#include <set>
using namespace LDBControlLayout;
int main() {
 std::set<std::string> ids;
 for(const auto& g:groups) {
  assert(ids.insert(g.id).second);
  if(g.parent[0])assert(findGroup(g.parent));
  auto p=&g;int depth=0;
  while(p->parent[0]){p=findGroup(p->parent);assert(++depth<=2);}
 }
 ids.clear();
 for(const auto& c:controls){assert(ids.insert(c.id).second);assert(findGroup(c.group));}
 auto expect=[](std::vector<std::string> configured,std::initializer_list<const char*> open) {
  auto result=expandedGroups(configured);
  for(auto* id:open)assert(result.count(id));
 };
 #if defined(LDB_ENABLE_FRAME_RELATIVE) || defined(LDB_RESOLUTION_RELATIVE_CANDIDATE)
 expect({"effectSize"},{"processing","setupSection"});
 assert(std::string(findControl("effectSize")->label)=="Effect Size");
#endif
 expect({"projectionModel"},{"projectionGroup","opticsSection"});
 expect({"projectionAmount"},{"projectionGroup","opticsSection"}); // Model Off with dormant values.
 expect({"projectionFieldAngle"},{"projectionGroup","opticsSection"}); // Zero-angle test.
 expect({"anamorphicFlareGhostAmount"},{"flareGhosts","anamorphicFlareGroup","lightSection"});
 expect({"diffractionRayAmount"},{"flareRays","anamorphicFlareGroup","lightSection"});
 expect({"vignetteMechanical"},{"vignette","imageCircle","lightSection"});
 expect({"depthMode"},{"depthGroup","pupilSection"});
 expect({"apertureResponse"},{"aperture","focusField","depthGroup","pupilSection","fieldShape","opticsSection"});
 expect({"opticalCenter"},{"opticsSection"});
 assert(!expandedGroups({"opticalCenter"}).count("geometry"));
 expect({"fieldCenter"},{"fieldShape","opticsSection"});
 expect({"refractiveIrregularity"},{"refractive","opticsSection"});
 expect({"prismAmount"},{"prism","fieldShape","opticsSection"});
 expect({"anamorphicAberration"},{"chromatic","pupilSection","fieldShape"});
 expect({"coma"},{"offAxis","pupilSection","highlightResponse","lightSection"});
 for(const auto& g:groups)assert(initiallyOpen(g.id)==(expandedGroups({}).count(g.id)!=0));
 expect({}, {"setupSection","presetGroup","processing"});
 expect({"projectionModel"}, {"setupSection","presetGroup","processing"});
 auto neutral=expandedGroups({});assert(neutral.size()==4);assert(!neutral.count("opticsSection"));
 assert(std::string(findControl("anamorphicSqueeze")->group)=="anamorphic");
 assert(std::string(findControl("swirl")->label)=="Geometric Swirl");
 assert(std::string(findControl("responseDefocusFalloff")->label)=="Full Defocus Distance");
 std::cout<<"PASS: complete unique layout, acyclic three-level maximum, configured child/ancestor expansion, dormant projection, mechanical coverage, flare and focus dependencies\n";
}
