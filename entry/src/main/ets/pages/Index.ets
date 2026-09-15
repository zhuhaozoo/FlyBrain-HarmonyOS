// 应用根页面：HdsNavigation 导航根容器（官方 UIDesign Kit），首页为 3D 场景页
import { HdsNavigation } from '@kit.UIDesignKit';
import { AboutPage } from './AboutPage';
import { BrainPage } from './BrainPage';
import { ScenePage } from './ScenePage';
import { SettingsPage } from './SettingsPage';

@Entry
@Component
struct Index {
  @Provide('nav') navStack: NavPathStack = new NavPathStack();

  @Builder
  PageMap(name: string) {
    if (name === 'brain') {
      BrainPage()
    } else if (name === 'settings') {
      SettingsPage()
    } else if (name === 'about') {
      AboutPage()
    }
  }

  build() {
    HdsNavigation(this.navStack) {
      ScenePage()
    }
    .navDestination(this.PageMap)
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
  }
}
