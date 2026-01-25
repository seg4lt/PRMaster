# How to Add Comments to PR Reviews

## Overview
PRMaster allows you to add inline comments to specific lines of code in a PR, as well as general review comments.

## Adding Comments

### Step 1: Open a PR for Review
1. Navigate to the "To Review" tab
2. Click on any PR in the list
3. Click the "Review PR" button in the detail panel
4. A new window will open showing the PR diff

### Step 2: Navigate Files
- Click on any file to expand it and see the diff
- Use keyboard shortcuts:
  - `j` - Move to next file
  - `k` - Move to previous file
  - `Space` - Toggle file expansion

### Step 3: Add Inline Comments
1. Find the line you want to comment on
2. Click the **"+" button** next to the line number
3. A comment editor will appear below the line
4. Type your comment
5. Click "Save" to save the draft comment
6. The comment will be stored locally until you submit your review

### Step 4: View Existing Comments
- Lines with existing comments show a **blue bubble icon** with the comment count
- Click the bubble to expand/collapse the comment thread
- Existing comments from other reviewers are displayed here

### Step 5: Submit Your Review
1. When you're done reviewing, click the "Submit Review" button
2. Choose an action:
   - **Approve** - Approve the PR
   - **Request Changes** - Request changes before merge
   - **Comment** - Leave general comments without approval
3. Optionally add a review summary
4. All your draft comments will be included automatically
5. Click "Submit" to finalize

## Keyboard Shortcuts for Comments

| Shortcut | Action |
|----------|--------|
| Click + button | Add new comment to line |
| Enter | Save current draft comment |
| Esc | Cancel/close draft comment |

## Comment Features

### Draft Comments
- Comments are saved as drafts until review submission
- You can edit or delete drafts before submitting
- Drafts are highlighted in blue

### Existing Comments
- View comments from other reviewers
- See comment author and timestamp
- Reply to existing comments (coming soon)

### Comment Indicators
- **Blue bubble with number**: Shows existing comment count
- **Plus icon**: Click to add new comment
- **Eye icon**: Mark file as viewed

## Tips

1. **Mark Files as Viewed**: Press `v` while viewing a file to mark it as viewed
2. **Track Progress**: The header shows "viewed/total" files
3. **Quick Approve**: Use the quick approve button in PRDetailView for fast approval
4. **Incremental Review**: If you've reviewed before, use "New Changes" to see only updates

## Troubleshooting

### Comments not showing?
- Make sure you've clicked "Preview PR" to load the diff
- Check that the file has comments (look for blue bubbles)
- Refresh the PR list to get latest comments

### Can't see comment button?
- Expand the file first by clicking on it
- Make sure you're in the diff view (not the list view)
- Check that you have permission to comment on the PR

### Draft comments disappeared?
- Drafts are stored locally and in memory
- They're submitted when you click "Submit Review"
- If you close the window without submitting, drafts may be lost

## Integration with GitHub

All comments submitted through PRMaster are stored on GitHub and:
- Visible in GitHub's web interface
- Synced with GitHub's review system
- Part of the permanent review record
- Can be edited/deleted on GitHub later
