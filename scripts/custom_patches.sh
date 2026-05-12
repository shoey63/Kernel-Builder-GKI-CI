#!/usr/bin/env bash
cd kernel_workspace/common || exit 1

echo ">>> EXPERIMENT: Cherry-picking Sumanth's DMA-BUF fix (228144d)..."

# This commit is already in your tree, but we are going to re-apply it as a local commit.
if git cherry-pick 228144d750eb06047b19a9e04612e6c63db01425; then
    echo ">>> SUCCESS: Commit re-applied locally."
else
    echo ">>> INFO: Git detected it's a duplicate or failed. Forcing a dummy change..."
    echo "// Stealth Test" >> drivers/dma-buf/dma-buf.c
    git add drivers/dma-buf/dma-buf.c
    git commit -m "STABLE: Force modification test"
fi

echo ">>> Hiding the modification from the index..."
git update-index --assume-unchanged drivers/dma-buf/dma-buf.c

# Final check: Does git think we are clean?
if git diff-index --quiet HEAD --; then
    echo ">>> Index reports CLEAN."
else
    echo ">>> Index reports DIRTY."
fi
