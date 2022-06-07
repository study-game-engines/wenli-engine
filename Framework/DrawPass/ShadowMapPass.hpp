#pragma once
#include "BaseDrawPass.hpp"

namespace My {
class ShadowMapPass : public BaseDrawPass {
   public:
    using BaseDrawPass::BaseDrawPass;
    ~ShadowMapPass() override = default;

    void BeginPass(Frame& frame) override {}
    void Draw(Frame& frame) final;
    void EndPass(Frame& frame) override {}
};
}  // namespace My
