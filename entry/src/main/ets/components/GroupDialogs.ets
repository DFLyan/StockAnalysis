import { ThemeColors, themeColors } from '../model/Theme';

/**
 * 新建分组对话框：自定义命名分组，名称 1-12 字符。
 */
@CustomDialog
export struct CreateGroupDialog {
  controller: CustomDialogController;
  onCreate: (name: string) => void = () => {
  };
  @State nameInput: string = '';
  @State errText: string = '';
  @StorageLink('theme_index') themeIndex: number = 0;

  private t(): ThemeColors {
    return themeColors(this.themeIndex);
  }

  build() {
    Column({ space: 16 }) {
      Text('新建分组')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.t().textPrimary)
        .width('100%')

      TextInput({ placeholder: '输入分组名称（如：核心持仓）' })
        .height(42)
        .fontSize(14)
        .fontColor(this.t().textPrimary)
        .placeholderColor(this.t().textTertiary)
        .placeholderFont({ size: 13 })
        .backgroundColor(this.t().inputBg)
        .borderRadius(10)
        .padding({ left: 12, right: 12 })
        .onChange((value: string) => {
          this.nameInput = value;
          this.errText = '';
        })

      if (this.errText !== '') {
        Text(this.errText)
          .fontSize(12)
          .fontColor('#FF6B6B')
          .width('100%')
      }

      Row({ space: 10 }) {
        Button('取消')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.t().textSecondary)
          .backgroundColor(this.t().inputBg)
          .borderRadius(12)
          .height(40)
          .layoutWeight(1)
          .onClick(() => {
            this.controller.close();
          })
        Button('创建')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .backgroundColor(this.t().accent)
          .borderRadius(12)
          .height(40)
          .layoutWeight(1)
          .onClick(() => {
            const name: string = this.nameInput.trim();
            if (name === '') {
              this.errText = '请输入分组名称';
              return;
            }
            if (name.length > 12) {
              this.errText = '名称最多 12 个字符';
              return;
            }
            this.onCreate(name);
            this.controller.close();
          })
      }
      .width('100%')
    }
    .padding(20)
    .width('86%')
    .backgroundColor(this.t().card)
    .borderRadius(16)
  }
}

/**
 * 选择分组对话框：加个股入自选时选择归属分组，空串表示不分组。
 */
@CustomDialog
export struct GroupPickerDialog {
  controller: CustomDialogController;
  @Prop hint: string = '';
  @Prop groups: string[] = [];
  onPick: (group: string) => void = () => {
  };
  @StorageLink('theme_index') themeIndex: number = 0;

  private t(): ThemeColors {
    return themeColors(this.themeIndex);
  }

  build() {
    Column({ space: 10 }) {
      Text(this.hint !== '' ? this.hint : '选择分组')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.t().textPrimary)
        .width('100%')

      Scroll() {
        Column({ space: 6 }) {
          ForEach(this.groups, (name: string) => {
            Row({ space: 10 }) {
              Column()
                .width(8)
                .height(8)
                .borderRadius(4)
                .backgroundColor(this.t().accent)
              Text(name)
                .fontSize(14)
                .fontColor(this.t().textPrimary)
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text('加入')
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.t().accent)
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 12, bottom: 12 })
            .backgroundColor(this.t().inputBg)
            .borderRadius(12)
            .onClick(() => {
              this.onPick(name);
              this.controller.close();
            })
          }, (name: string) => name)

          Row({ space: 8 }) {
            Text('不分组，仅加入自选')
              .fontSize(13)
              .fontColor(this.t().textSecondary)
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ left: 14, right: 14, top: 11, bottom: 11 })
          .borderRadius(12)
          .border({ width: 1, color: this.t().cardBorder })
          .onClick(() => {
            this.onPick('');
            this.controller.close();
          })
        }
        .width('100%')
      }
      .constraintSize({ maxHeight: 320 })
      .width('100%')

      Button('取消')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.t().textSecondary)
        .backgroundColor(this.t().inputBg)
        .borderRadius(12)
        .height(38)
        .width('100%')
        .onClick(() => {
          this.controller.close();
        })
    }
    .padding(20)
    .width('86%')
    .backgroundColor(this.t().card)
    .borderRadius(16)
  }
}
