; RUN: llc -amdgpu-scalarize-global-loads=false -march=amdgcn -mcpu=gfx900 -mattr=-flat-for-global -verify-machineinstrs < %s | FileCheck --check-prefix=GCN %s

; indexing of vectors.

; Subtest below moved from file test/CodeGen/AMDGPU/indirect-addressing-si.ll
; to avoid gfx9 scheduling induced issues.


; GCN-LABEL: {{^}}insert_vgpr_offset_multiple_in_block:
; GCN-DAG: s_load_dwordx16 s{{\[}}[[S_ELT0:[0-9]+]]:[[S_ELT15:[0-9]+]]{{\]}}
; GCN-DAG: {{buffer|flat|global}}_load_dword [[IDX0:v[0-9]+]]
; GCN-DAG: v_mov_b32 [[INS0:v[0-9]+]], 62

; GCN-DAG: v_mov_b32_e32 v[[VEC_ELT15:[0-9]+]], s[[S_ELT15]]
; GCN-DAG: v_mov_b32_e32 v[[VEC_ELT0:[0-9]+]], s[[S_ELT0]]

; GCN: v_cmp_eq_u32_e32
; GCN-COUNT-32: v_cndmask_b32

; GCN-COUNT-4: buffer_store_dwordx4
define amdgpu_kernel void @insert_vgpr_offset_multiple_in_block(<16 x i32> addrspace(1)* %out0, <16 x i32> addrspace(1)* %out1, i32 addrspace(1)* %in, <16 x i32> %vec0) #0 {
entry:
  %id = call i32 @llvm.amdgcn.workitem.id.x() #1
  %id.ext = zext i32 %id to i64
  %gep = getelementptr inbounds i32, i32 addrspace(1)* %in, i64 %id.ext
  %idx0 = load volatile i32, i32 addrspace(1)* %gep
  %idx1 = add i32 %idx0, 1
  %live.out.val = call i32 asm sideeffect "v_mov_b32 $0, 62", "=v"()
  %vec1 = insertelement <16 x i32> %vec0, i32 %live.out.val, i32 %idx0
  %vec2 = insertelement <16 x i32> %vec1, i32 63, i32 %idx1
  store volatile <16 x i32> %vec2, <16 x i32> addrspace(1)* %out0
  %cmp = icmp eq i32 %id, 0
  br i1 %cmp, label %bb1, label %bb2

bb1:
  store volatile i32 %live.out.val, i32 addrspace(1)* undef
  br label %bb2

bb2:
  ret void
}

; Avoid inserting extra v_mov from copies within the vgpr indexing sequence. The
; gpr_idx mode switching sequence is expanded late for this reason.

; GCN-LABEL: {{^}}insert_w_offset_multiple_in_block

; GCN: s_set_gpr_idx_on
; GCN-NEXT: v_mov_b32_e32
; GCN-NEXT: s_set_gpr_idx_off

; GCN: s_set_gpr_idx_on
; GCN-NEXT: v_mov_b32_e32
; GCN-NOT: v_mov_b32_e32
; GCN-NEXT: s_set_gpr_idx_off
define amdgpu_kernel void @insert_w_offset_multiple_in_block(<16 x float> addrspace(1)* %out1, i32 %in) #0 {
entry:
  %add1 = add i32 %in, 1
  %ins1 = insertelement <16 x float> <float 1.0, float 2.0, float 3.0, float 4.0, float 5.0, float 6.0, float 7.0, float 8.0, float 9.0, float 10.0, float 11.0, float 12.0, float 13.0, float 14.0, float 15.0, float 16.0>, float 17.0, i32 %add1
  %add2 = add i32 %in, 2
  %ins2 = insertelement <16 x float> %ins1, float 17.0, i32 %add2
  store <16 x float> %ins1, <16 x float> addrspace(1)* %out1
  %out2 = getelementptr <16 x float>, <16 x float> addrspace(1)* %out1, i32 1
  store <16 x float> %ins2, <16 x float> addrspace(1)* %out2

  ret void
}

declare hidden void @foo()

; For functions with calls, we were not accounting for m0_lo16/m0_hi16
; uses on the BUNDLE created when expanding the insert register pseudo.
; GCN-LABEL: {{^}}insertelement_with_call:
; GCN: s_set_gpr_idx_on s{{[0-9]+}}, gpr_idx(DST)
; GCN-NEXT: s_waitcnt vmcnt(0)
; GCN-NEXT: v_mov_b32_e32 {{v[0-9]+}}, 8
; GCN-NEXT: s_set_gpr_idx_off
; GCN: s_swappc_b64
define amdgpu_kernel void @insertelement_with_call(<16 x i32> addrspace(1)* %ptr, i32 %idx) #0 {
  %vec = load <16 x i32>, <16 x i32> addrspace(1)* %ptr
  %i6 = insertelement <16 x i32> %vec, i32 8, i32 %idx
  call void @foo()
  store <16 x i32> %i6, <16 x i32> addrspace(1)* null
  ret void
}

declare i32 @llvm.amdgcn.workitem.id.x() #1
declare void @llvm.amdgcn.s.barrier() #2

attributes #0 = { nounwind }
