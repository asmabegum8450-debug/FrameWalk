# FrameWalk - Developer Guide

An app designed to help you find inspiration and never run out of things to photograph, all while taking relaxing walks through your community.

## Links
- [**User Guide**](https://docs.google.com/document/d/10nhHqrpsAJrck1gYdsq_RcXdFm_2nfoR1fQ4NzOpduM/edit?usp=sharing)
- [Living Document](https://docs.google.com/document/d/1lYug-M3YyP1dTDqYPlPpnL4UAtH1hgJSdiU_M_lnueI/edit?tab=t.0)
- [Figma](https://www.figma.com/design/9afJm17FYCXVwcnU6hJhCi/CSE-403?node-id=0-1&m=dev&t=1FsT888g7EucfzPl-1)
- Setup Instructions
   - [Android Setup](frame_walk/docs/android-setup.md)
   - [iOS Setup](frame_walk/docs/ios-setup.md)
   - [Firebase Setup](frame_walk/docs/firebase-setup.md)
   - [GPS Tracking](frame_walk/docs/gps-tracking.md)
- [Coding Guidelines](frame_walk/docs/coding-guidelines.md)

## Layout

```bash

FrameWalk/frame_walk/
lib/
├── main.dart
├── firebase_options.dart
├── backend/
│   ├── providers/
│   │   └── route_provider.dart
│   ├── services/
│   │   ├── auth_service.dart
│   │   ├── location_source.dart
│   │   ├── prompt_generator.dart
│   │   ├── route_manager.dart
│   │   ├── route_progress_tracker.dart
│   │   ├── walk_repository.dart
│   │   └── walk_tracking_service.dart
├── frontend/
│   ├── screens/
│   │   ├── account_page.dart
│   │   ├── active_walk_page.dart
│   │   ├── activity page.dart
│   │   ├── auth_gate.dart
│   │   ├── create_account_page.dart
│   │   ├── home_page.dart
│   │   ├── landing_page.dart
│   │   ├── login_page.dart
│   │   ├── map_page.dart
│   │   └── route_info_page.dart
│   ├── theme/
│   │   └── app_theme.dart
│   ├── widgets/
│   │   ├── bottom_nav.dart
│   │   ├── route_card.dart
│   │   ├── route_filter_chips.dart
│   │   └── route_search_bar.dart
├── models/
│   │   ├── location_point.dart
│   │   ├── mock_route_data.dart
│   │   ├── route_stop.dart
│   │   ├── user_account.dart
│   │   └── walked_route.dart
test/
├── backend/
│   ├── providers/
│   │   └── route_provider_test.dart
│   ├── services/
│   │   ├── auth_service_test.dart
│   │   ├── prompt_generator_test.dart
│   │   ├── route_manager_test.dart
│   │   ├── route_progress_tracker_test.dart
│   │   ├── walk_repository_test.dart
│   │   └── walk_tracking_service_test.dart
├── fakes/
│   │   └── fake_location_source.dart
├── frontend/
│   ├── screens/
│   │   └── active_walk_page_test.dart
│   └── auth_flow_test.dart
docs/
├── android-setup.md
├── coding-guidelines.md
├── firebase-setup.md
├── gps-tracking.md
├── ios-setup.md
.gitignore
LICENSE
README.md

```

## Goals

Users will be able to explore their surrounding area and find inspiration in their environment through photography prompts along routes/locations around the University of Washington, Seattle, campus.

Whether a user’s list of ideas has met its end or has struggled to even start, lack of inspiration can demotivate, kill consistency, and vice versa. We don’t want users to be stuck wishing they could be more creative and feeling like they need a lucky epiphany instead of a reliable source to offer an aesthetic vision.

Since people have their typical routes around school, work, and their general neighborhood, new places and scenery lie waiting to be discovered. Offering users a new, specific path with curated photo prompts will let them literally see the space through a new lens.
As the seasons change, we want users to reflect on a detailed catalog of their exploration and personal perspective along with their ever-changing environment.

## Functional Use Cases
- Account creation, logging in, and logging out
- Filtering and searching routes on home page and map page
- Viewing route information when clicking a route card and starting a route - includes seeing notifications in app when near a stop but not when the app is closed.
- Saving a route and seeing it in the activity page

## Adding Tests
- All tests should exist in the frame_walk/test folder (outside of lib) under either frame_walk/test/backend or frame_walk/test/frontend depending on the test. Mocks for testing should go in frame_walk/test/fakes.
   - The “flutter test” command will look in the top level frame_walk/test/ folder and will only run files that end in _test.dart. Ensure all files for testing end in _test.dart so that they are run.
   -  Files in frame_walk/test/fakes should not end in _test.dart as files in this folder should only be mock data for testing and not hold any tests themselves
- If adding to an existing test suite (auth_service_test.dart, prompt_generator_test.dart, route_manager_test.dart, route_progress_tracker_test.dart, walk_repository_test.dart, walk_tracking_service_test.dart, route_provider_test.dart, active_walk_page_test.dart, and auth_flow_test.dart), add to the existing file and it will be linted and run upon CI trigger
- New test files should be created when they’re for a unit/component that hasn’t been tested and should only test one logical unit. New files should use proper syntax
   - Tests should use group() from the flutter_test package to group together test() calls from the flutter_test package so that tests are grouped and run together logically. Each group() and test() should have descriptive description fields.
   - Each test() call should contain expect(a, b) calls with two parameters passed in (a, b). The first (a) should be the actual value where the second (b) is the expected value. 