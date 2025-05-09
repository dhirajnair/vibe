import { test, expect } from '@playwright/test';

test('LinkedIn Post Creation', async ({ page }) => {
  // Set a longer timeout for this test
  test.setTimeout(120000);

  // Input parameters
  const username = process.env.LINKEDIN_USERNAME || '';
  const password = process.env.LINKEDIN_PASSWORD || '';
  const postContent = process.env.POST_CONTENT || '';

  // Validate inputs
  if (!username || !password || !postContent) {
    throw new Error('Please provide LINKEDIN_USERNAME, LINKEDIN_PASSWORD, and POST_CONTENT environment variables');
  }

  // Navigate to LinkedIn
  await page.goto('https://www.linkedin.com/hp');
  
  // Sign in process
  await page.getByRole('link', { name: 'Sign in', exact: true }).click();
  await page.getByRole('textbox', { name: 'Email or phone' }).fill(username);
  await page.getByRole('textbox', { name: 'Password' }).fill(password);
  await page.getByRole('button', { name: 'Sign in', exact: true }).click();

  // Wait for the feed to load
  await page.waitForSelector('div.feed-shared-update-v2', { timeout: 60000 });

  // Create post
  await page.getByRole('button', { name: 'Start a post' }).click();
  
  // Wait for the post modal to appear
  await page.waitForSelector('div.ql-editor', { timeout: 30000 });
  await page.getByRole('textbox', { name: 'Text editor for creating' }).fill(postContent);
  
  // Wait a bit before clicking post
  await page.waitForTimeout(2000);
  await page.getByRole('button', { name: 'Post', exact: true }).click();

  // Wait for the post to be published
  await page.waitForSelector('div.feed-shared-update-v2', { timeout: 30000 });
}); 