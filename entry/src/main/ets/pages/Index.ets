import { preferences } from '@kit.ArkData';
import { fileIo } from '@kit.CoreFileKit';
import picker from '@ohos.file.picker';

interface Segment {
  id: number;
  source: string;
  target: string;
  note: string;
}

interface Term {
  source: string;
  target: string;
  note: string;
}

interface Project {
  id: string;
  name: string;
}

interface ProjectData {
  name: string;
  segments: Segment[];
  terms: Term[];
}

@Entry
@Component
struct Index {
  @State segments: Segment[] = [];
  @State terms: Term[] = [];
  @State projects: Project[] = [];
  @State selectedId: number = -1;
  @State saved: boolean = true;
  @State loaded: boolean = false;
  @State projectName: string = '我的翻译作业';
  @State activeProjectId: string = 'default';
  @State store: preferences.Preferences | undefined = undefined;
  @State query: string = '';
  @State filter: string = '全部';
  @State showProjects: boolean = false;
  @State showCreateProject: boolean = false;
  @State draftProjectName: string = '';
  @State statusMessage: string = '';

  async aboutToAppear(): Promise<void> {
    try {
      const value: preferences.Preferences = await preferences.getPreferences(getContext(this), { name: 'parallel_text_studio' });
      this.store = value;
      const projectsRaw: preferences.ValueType = await value.get('projects', '');
      const storedProject: preferences.ValueType = await value.get('activeProjectId', 'default');
      const segmentsRaw: preferences.ValueType = await value.get('segments', '');
      const termsRaw: preferences.ValueType = await value.get('terms', '');
      const projectRawName: preferences.ValueType = await value.get('projectName', '我的翻译作业');
        if (typeof projectsRaw === 'string' && projectsRaw.length > 0) this.projects = JSON.parse(projectsRaw) as Project[];
        if (this.projects.length === 0) this.projects = [{ id: 'default', name: '我的翻译作业' }];
        const storedProjectId: string = typeof storedProject === 'string' && storedProject.length > 0 ? storedProject : 'default';
        this.activeProjectId = this.projects.some((project: Project) => project.id === storedProjectId) ? storedProjectId : this.projects[0].id;
        const legacySegments: Segment[] = typeof segmentsRaw === 'string' && segmentsRaw.length > 0 ? JSON.parse(segmentsRaw) as Segment[] : [];
        const legacyTerms: Term[] = typeof termsRaw === 'string' && termsRaw.length > 0 ? JSON.parse(termsRaw) as Term[] : [];
        const legacyName: string = typeof projectRawName === 'string' && projectRawName.length > 0 ? projectRawName : '我的翻译作业';
        const projectKey: string = `project_${this.activeProjectId}`;
        const projectRaw: preferences.ValueType = await value.get(projectKey, '');
          if (typeof projectRaw === 'string' && projectRaw.length > 0) {
            const data: ProjectData = JSON.parse(projectRaw) as ProjectData;
            this.segments = data.segments ?? [];
            this.terms = data.terms ?? [];
            this.projectName = data.name ?? legacyName;
          } else {
            this.segments = legacySegments;
            this.terms = legacyTerms;
            this.projectName = legacyName;
          }
          this.selectedId = this.segments.length > 0 ? this.segments[0].id : -1;
          this.loaded = true;
          this.saved = true;
          this.persist();
    } catch (_error) {
      this.statusMessage = '本地数据载入失败';
    }
  }

  private persist(): void {
    const store = this.store;
    if (!this.loaded || !store) return;
    this.saved = false;
    const projectData: ProjectData = { name: this.projectName, segments: this.segments, terms: this.terms };
    const writes: Promise<void>[] = [
      store.put(`project_${this.activeProjectId}`, JSON.stringify(projectData)),
      store.put('projects', JSON.stringify(this.projects)),
      store.put('activeProjectId', this.activeProjectId),
      store.put('segments', JSON.stringify(this.segments)),
      store.put('terms', JSON.stringify(this.terms)),
      store.put('projectName', this.projectName)
    ];
    Promise.all(writes).then(() => store.flush()).then(() => { this.saved = true; });
  }

  private get missingCount(): number {
    return this.segments.filter((item: Segment) => item.source.trim().length > 0 && item.target.trim().length === 0).length;
  }

  private get termIssueCount(): number {
    return this.segments.filter((item: Segment) => this.termHits(item).length > 0).length;
  }

  private get sourceCount(): number {
    return this.segments.filter((item: Segment) => item.source.trim().length > 0).length;
  }

  private get translatedCount(): number {
    return this.segments.filter((item: Segment) => item.source.trim().length > 0 && item.target.trim().length > 0).length;
  }

  private visibleSegments(): Segment[] {
    return this.segments.filter((item: Segment) => {
      const matchesQuery: boolean = this.query.trim().length === 0 || item.source.toLowerCase().includes(this.query.toLowerCase()) ||
        item.target.toLowerCase().includes(this.query.toLowerCase()) || item.note.toLowerCase().includes(this.query.toLowerCase());
      const matchesFilter: boolean = this.filter === '全部' ||
        (this.filter === '待翻译' && item.source.trim().length > 0 && item.target.trim().length === 0) ||
        (this.filter === '术语问题' && this.termHits(item).length > 0);
      return matchesQuery && matchesFilter;
    });
  }

  private termHits(segment: Segment): string[] {
    const found: string[] = [];
    this.terms.forEach((term: Term) => {
      if (term.source.trim().length > 0 && term.target.trim().length > 0 && segment.source.toLowerCase().includes(term.source.toLowerCase())) {
        if (segment.target.trim().length === 0 || !segment.target.includes(term.target.trim())) found.push(term.source);
      }
    });
    return found;
  }

  private updateSegment(id: number, field: string, value: string): void {
    this.segments = this.segments.map((item: Segment) => {
      if (item.id !== id) return item;
      if (field === 'source') return { id: item.id, source: value, target: item.target, note: item.note } as Segment;
      if (field === 'target') return { id: item.id, source: item.source, target: value, note: item.note } as Segment;
      return { id: item.id, source: item.source, target: item.target, note: value } as Segment;
    });
    this.persist();
  }

  private addSegment(): void {
    const nextId = this.segments.length > 0 ? Math.max(...this.segments.map((item: Segment) => item.id)) + 1 : 1;
    this.segments = [...this.segments, { id: nextId, source: '', target: '', note: '' }];
    this.selectedId = nextId;
    this.persist();
  }

  private removeSegment(id: number): void {
    this.segments = this.segments.filter((item: Segment) => item.id !== id);
    if (this.selectedId === id) this.selectedId = this.segments.length > 0 ? this.segments[0].id : -1;
    this.persist();
  }

  private addTerm(): void {
    this.terms = [...this.terms, { source: '', target: '', note: '' }];
    this.persist();
  }

  private updateTerm(index: number, field: string, value: string): void {
    this.terms = this.terms.map((term: Term, i: number) => {
      if (i !== index) return term;
      if (field === 'source') return { source: value, target: term.target, note: term.note } as Term;
      if (field === 'target') return { source: term.source, target: value, note: term.note } as Term;
      return { source: term.source, target: term.target, note: value } as Term;
    });
    this.persist();
  }

  private removeTerm(index: number): void {
    this.terms = this.terms.filter((_term: Term, i: number) => i !== index);
    this.persist();
  }

  private createProject(): void {
    const name = this.draftProjectName.trim();
    if (name.length === 0) return;
    const project: Project = { id: `${Date.now()}`, name: name };
    this.projects = [...this.projects, project];
    const store = this.store;
    if (!store) return;
    const currentData: ProjectData = { name: this.projectName, segments: this.segments, terms: this.terms };
    Promise.all([store.put(`project_${this.activeProjectId}`, JSON.stringify(currentData)), store.flush()]).then(() => {
      this.draftProjectName = '';
      this.showCreateProject = false;
      this.loadProject(project, store);
    });
  }

  private switchProject(project: Project): void {
    if (project.id === this.activeProjectId) {
      this.showProjects = false;
      return;
    }
    const store = this.store;
    if (!store) return;
    const previousId: string = this.activeProjectId;
    const previousData: ProjectData = { name: this.projectName, segments: this.segments, terms: this.terms };
    this.saved = false;
    store.put(`project_${previousId}`, JSON.stringify(previousData)).then(() => store.flush()).then(() => {
      this.loadProject(project, store);
    });
  }

  private loadProject(project: Project, store: preferences.Preferences): void {
    this.projectName = project.name;
    this.activeProjectId = project.id;
    this.loaded = false;
    store.get(`project_${project.id}`, '').then((raw: preferences.ValueType) => {
      if (typeof raw === 'string' && raw.length > 0) {
        const data: ProjectData = JSON.parse(raw) as ProjectData;
        this.projectName = data.name ?? project.name;
        this.segments = data.segments ?? [];
        this.terms = data.terms ?? [];
      } else {
        this.segments = [];
        this.terms = [];
      }
      this.selectedId = this.segments.length > 0 ? this.segments[0].id : -1;
      this.loaded = true;
      this.saved = true;
      this.showProjects = false;
      this.persist();
    });
  }

  private async importFile(): Promise<void> {
    try {
      const documentPicker = new picker.DocumentViewPicker(getContext(this));
      const uris: Array<string> = await documentPicker.select({ fileSuffixFilters: ['平行文本文件|json,txt,tsv'] });
      if (uris.length === 0) return;
      const context = getContext(this);
      const localPath: string = `${context.filesDir}/parallel_text_import.tmp`;
      await fileIo.copyFile(uris[0], localPath);
      const content: string = await fileIo.readText(localPath);
      if (content.trim().startsWith('{')) {
        const data: ProjectData = JSON.parse(content) as ProjectData;
        const importedSegments: Segment[] = data.segments;
        const importedTerms: Term[] = data.terms;
        this.projectName = data.name ?? this.projectName;
        this.segments = importedSegments ?? [];
        this.terms = importedTerms ?? [];
      } else {
        const lines: string[] = content.replace(/\r/g, '').split('\n').filter((line: string) => line.length > 0);
        const rows: string[][] = lines.map((line: string) => line.split('\t').map((cell: string) => cell.replace(/\\n/g, '\n').replace(/\\t/g, '\t').replace(/\\\\/g, '\\')));
        const first: string[] = rows.length > 0 ? rows[0] : [];
        const hasHeader: boolean = first.length > 0 && first[0].toLowerCase() === 'source';
        const dataRows: string[][] = hasHeader ? rows.slice(1) : rows;
        this.segments = dataRows.map((row: string[], index: number) => ({ id: index + 1, source: row[0] ?? '', target: row[1] ?? '', note: row[2] ?? '' } as Segment));
      }
      this.selectedId = this.segments.length > 0 ? this.segments[0].id : -1;
      this.persist();
      this.statusMessage = `已导入 ${this.segments.length} 个段落`;
    } catch (_error) {
      this.statusMessage = '导入失败，请检查文件格式';
    }
  }

  private async exportFile(asTsv: boolean): Promise<void> {
    try {
      const documentPicker = new picker.DocumentViewPicker(getContext(this));
      const suffix: string = asTsv ? 'tsv' : 'json';
      const content: string = asTsv ? this.toTsv() : JSON.stringify({ format: 'parallel-text-studio', version: 1, name: this.projectName, segments: this.segments, terms: this.terms }, null, 2);
      const uris: Array<string> = await documentPicker.save({ newFileNames: [`${this.projectName}.${suffix}`], fileSuffixChoices: [suffix] });
      if (uris.length === 0) return;
      const context = getContext(this);
      const localPath: string = `${context.filesDir}/parallel_text_export.tmp`;
      const file = await fileIo.open(localPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd, content);
      fileIo.closeSync(file.fd);
      await fileIo.copyFile(localPath, uris[0]);
      this.statusMessage = '文件已导出';
    } catch (_error) {
      this.statusMessage = '导出失败，请重试';
    }
  }

  private toTsv(): string {
    const escapeCell = (value: string): string => value.replace(/\\/g, '\\\\').replace(/\t/g, '\\t').replace(/\r?\n/g, '\\n');
    return ['source\ttarget\tnote', ...this.segments.map((item: Segment) => `${escapeCell(item.source)}\t${escapeCell(item.target)}\t${escapeCell(item.note)}`)].join('\n');
  }

  build() {
    Column() {
      Row() {
        Column({ space: 2 }) {
          Text('平行文本').fontSize(20).fontWeight(FontWeight.Bold).fontColor('#17231F');
          Text('TRANSLATION WORKSPACE').fontSize(9).fontWeight(FontWeight.Medium).fontColor('#74827B');
        }.alignItems(HorizontalAlign.Start);
        Blank();
        Text(this.statusMessage.length > 0 ? this.statusMessage : (!this.loaded ? '载入中…' : (this.saved ? '已保存到本机' : '保存中…')))
          .fontSize(11).fontColor(this.saved ? '#367B62' : '#8B6B37');
      }.width('100%').padding({ left: 20, right: 20, top: 13, bottom: 12 });

      Row() {
        Column({ space: 7 }) {
          Row({ space: 9 }) {
            Text(this.projectName).fontSize(18).fontWeight(FontWeight.Medium).fontColor('#1D2A25');
            Text('⌄').fontSize(13).fontColor('#63746B').onClick(() => { this.showProjects = !this.showProjects; });
          }.onClick(() => { this.showProjects = !this.showProjects; });
          Row({ space: 8 }) {
            Text('原文  →  译文').fontSize(11).fontColor('#50685E').backgroundColor('#E8F0EB').padding({ left: 10, right: 10, top: 6, bottom: 6 }).borderRadius(4);
            Text('本机自动保存').fontSize(10).fontColor('#78867E');
          }
        }.alignItems(HorizontalAlign.Start);
        Blank();
        Button('导入').height(34).backgroundColor('#EAF0EC').fontColor('#30443A').onClick(() => this.importFile());
        Button('导出 JSON').height(34).margin({ left: 7 }).backgroundColor('#1E3A32').fontColor(Color.White).onClick(() => this.exportFile(false));
        Button('TSV').height(34).margin({ left: 7 }).backgroundColor('#EAF0EC').fontColor('#30443A').onClick(() => this.exportFile(true));
      }.width('100%').padding({ left: 22, right: 22, top: 12, bottom: 12 }).backgroundColor('#F4F7F5');

      if (this.showProjects) {
        Column({ space: 8 }) {
          Row() {
            Text('项目').fontSize(12).fontWeight(FontWeight.Medium).fontColor('#27342E');
            Blank();
            Text('关闭').fontSize(11).fontColor('#63746B').onClick(() => { this.showProjects = false; });
          }.width('100%');
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.projects, (project: Project) => {
              Button(project.name).height(32).backgroundColor(project.id === this.activeProjectId ? '#DDE9E1' : '#F1F4F2')
                .fontColor('#30443A').onClick(() => this.switchProject(project));
            }, (project: Project) => project.id);
            Button('+ 新建项目').height(32).backgroundColor('#1E3A32').fontColor(Color.White).onClick(() => { this.showCreateProject = true; });
          }
        }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off);
          if (this.showCreateProject) {
            Row({ space: 8 }) {
              TextInput({ text: this.draftProjectName, placeholder: '输入项目名称' }).layoutWeight(1).height(38).backgroundColor('#F4F7F5')
                .onChange((value: string) => { this.draftProjectName = value; });
              Button('创建').height(34).backgroundColor('#1E3A32').fontColor(Color.White).onClick(() => this.createProject());
              Button('取消').height(34).backgroundColor('#EAF0EC').fontColor('#30443A').onClick(() => { this.showCreateProject = false; });
            }.width('100%');
          }
        }.width('100%').padding({ left: 22, right: 22, top: 12, bottom: 12 }).backgroundColor('#FFFFFF');
      }

      Row() {
        Column({ space: 3 }) {
          Text('对照编辑').fontSize(17).fontWeight(FontWeight.Medium).fontColor('#1C2923');
          Text('逐段核对译文、遗漏与术语').fontSize(11).fontColor('#7A8781');
        }.alignItems(HorizontalAlign.Start);
        Blank();
        Column({ space: 4 }) {
          Text(`${this.translatedCount} / ${this.sourceCount}`).fontSize(14).fontWeight(FontWeight.Medium).fontColor('#264A3D');
          Text('已完成译文').fontSize(9).fontColor('#7C8982');
        }.alignItems(HorizontalAlign.End).margin({ right: 15 });
        Column({ space: 4 }) {
          Text(`${this.missingCount + this.termIssueCount}`).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.missingCount + this.termIssueCount > 0 ? '#B77D32' : '#264A3D');
          Text('待检查项').fontSize(9).fontColor('#7C8982');
        }.alignItems(HorizontalAlign.End).margin({ right: 15 });
        Button('+ 新增段落').height(34).enabled(this.loaded).backgroundColor('#1E3A32').fontColor(Color.White).onClick(() => this.addSegment());
      }.width('100%').padding({ left: 22, right: 22, top: 15, bottom: 12 });

      Row({ space: 8 }) {
        TextInput({ text: this.query, placeholder: '搜索原文、译文或备注' }).layoutWeight(1).height(36).fontSize(12).backgroundColor('#F1F4F2').borderRadius(4)
          .onChange((value: string) => { this.query = value; });
        ForEach(['全部', '待翻译', '术语问题'], (label: string) => {
          Text(label).fontSize(11).fontColor(this.filter === label ? '#FFFFFF' : '#52635A')
            .backgroundColor(this.filter === label ? '#365748' : '#EDF1EE')
            .padding({ left: 11, right: 11, top: 9, bottom: 9 }).borderRadius(4)
            .onClick(() => { this.filter = label; });
        }, (label: string) => label);
      }.width('100%').padding({ left: 22, right: 22, bottom: 10 });

      Row() {
        Column() {
          Row() {
            Text('#').width(36).fontSize(10).fontColor('#88958E');
            Text('原文').layoutWeight(1).fontSize(11).fontWeight(FontWeight.Medium).fontColor('#64726B');
            Text('译文').layoutWeight(1).fontSize(11).fontWeight(FontWeight.Medium).fontColor('#64726B');
            Text('备注').width(100).fontSize(10).fontColor('#88958E');
            Text('').width(24);
          }.padding({ left: 10, right: 10, top: 10, bottom: 10 }).backgroundColor('#F2F5F3');
          if (this.visibleSegments().length === 0) {
            Column({ space: 8 }) {
              Text(this.segments.length === 0 ? '从导入文件开始，或新增一个段落' : '没有符合条件的段落').fontSize(13).fontColor('#68776F');
              if (this.segments.length === 0) {
                Button('新增第一段').height(34).backgroundColor('#1E3A32').fontColor(Color.White).onClick(() => this.addSegment());
              }
            }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
          } else {
            Scroll() {
              Column() {
                ForEach(this.visibleSegments(), (item: Segment) => { this.segmentRow(item); }, (item: Segment) => `${item.id}`);
              }
            }.layoutWeight(1).scrollBar(BarState.Auto);
          }
        }.layoutWeight(1).height('100%').border({ color: '#E2E8E4', width: 1 }).borderRadius(5).clip(true);

        Column({ space: 12 }) {
          this.insightPanel();
          this.glossaryPanel();
        }.width(270).height('100%').margin({ left: 14 });
      }.layoutWeight(1).width('100%').padding({ left: 22, right: 22, bottom: 18 }).alignItems(VerticalAlign.Top);
    }.width('100%').height('100%').backgroundColor('#FBFCFB');
  }

  @Builder
  segmentRow(item: Segment) {
    Column() {
      Row() {
        Text(`${item.id}`.padStart(2, '0')).width(36).fontSize(10).fontColor('#98A29D').align(Alignment.Top);
        TextArea({ text: item.source, placeholder: '输入原文…' }).layoutWeight(1).height(74).fontSize(12).fontColor('#27342E')
          .enabled(this.loaded).backgroundColor(Color.Transparent).border({ width: 0 }).padding({ left: 6, right: 8, top: 4, bottom: 4 })
          .onChange((value: string) => this.updateSegment(item.id, 'source', value));
        TextArea({ text: item.target, placeholder: '输入译文…' }).layoutWeight(1).height(74).fontSize(12).fontColor('#27342E')
          .enabled(this.loaded).backgroundColor(item.target.trim().length === 0 ? '#FFF9EF' : Color.Transparent).border({ width: 0 }).padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .onChange((value: string) => this.updateSegment(item.id, 'target', value));
        TextArea({ text: item.note, placeholder: '段落备注…' }).width(100).height(74).fontSize(10).fontColor('#718078')
          .enabled(this.loaded).backgroundColor(Color.Transparent).border({ width: 0 }).padding({ left: 5, right: 2, top: 4, bottom: 4 })
          .onChange((value: string) => this.updateSegment(item.id, 'note', value));
        Text('×').width(24).fontSize(14).fontColor('#A16E65').align(Alignment.Top).onClick(() => this.removeSegment(item.id));
      }.alignItems(VerticalAlign.Top).padding({ left: 10, right: 10, top: 10, bottom: 3 }).backgroundColor(this.selectedId === item.id ? '#FAFCFA' : Color.White)
        .onClick(() => { this.selectedId = item.id; });
      Row({ space: 5 }) {
        Text((item.source.trim().length > 0 && item.target.trim().length === 0) || this.termHits(item).length > 0 ? '!' : '✓').fontSize(9).fontColor(((item.source.trim().length > 0 && item.target.trim().length === 0) || this.termHits(item).length > 0) ? '#A77732' : '#769083');
        Text(item.source.trim().length > 0 && item.target.trim().length === 0 ? '译文为空，可能遗漏' : (this.termHits(item).length > 0 ? `术语待核对：${this.termHits(item).join('、')}` : '已填写')).fontSize(9)
          .fontColor(((item.source.trim().length > 0 && item.target.trim().length === 0) || this.termHits(item).length > 0) ? '#A77732' : '#769083');
      }.margin({ left: 46, bottom: 7 });
      Divider().color('#EDF0EE').strokeWidth(1);
    }.width('100%');
  }

  @Builder
  insightPanel() {
    Column({ space: 11 }) {
      Row() {
        Text('检查概览').fontSize(13).fontWeight(FontWeight.Medium).fontColor('#26342D');
        Blank();
        Text(`${this.sourceCount} 段原文`).fontSize(10).fontColor('#7C8982');
      }
      Row() {
        Column({ space: 4 }) {
          Text(`${this.translatedCount}/${this.sourceCount}`).fontSize(20).fontWeight(FontWeight.Medium).fontColor('#264A3D');
          Text('译文覆盖').fontSize(10).fontColor('#7C8982');
        }.alignItems(HorizontalAlign.Start).layoutWeight(1);
        Divider().vertical(true).height(35).color('#E5EAE7');
        Column({ space: 4 }) {
          Text(`${this.missingCount}`).fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.missingCount > 0 ? '#B77D32' : '#264A3D');
          Text('译文遗漏').fontSize(10).fontColor('#7C8982');
        }.alignItems(HorizontalAlign.Start).layoutWeight(1).margin({ left: 14 });
      }.padding({ top: 4, bottom: 4 });
      Text(`${this.termIssueCount} 段存在术语用词问题`).fontSize(10).fontColor(this.termIssueCount > 0 ? '#936A34' : '#4C7561')
        .width('100%').padding(9).backgroundColor(this.termIssueCount > 0 ? '#FBF5EA' : '#F0F6F2').borderRadius(3);
    }.width('100%').padding(13).backgroundColor(Color.White).border({ color: '#E4EAE6', width: 1 }).borderRadius(5).alignItems(HorizontalAlign.Start);
  }

  @Builder
  glossaryPanel() {
    Column({ space: 9 }) {
      Row() {
        Column({ space: 2 }) {
          Text('术语库').fontSize(13).fontWeight(FontWeight.Medium).fontColor('#26342D');
          Text('在原文命中时检查标准译法').fontSize(9).fontColor('#87938D');
        }.alignItems(HorizontalAlign.Start);
        Blank();
        Text('+').fontSize(18).fontColor('#47785F').onClick(() => { if (this.loaded) this.addTerm(); });
      }
      Row() {
        Text('原文词').layoutWeight(1).fontSize(9).fontColor('#88958E');
        Text('标准译法').layoutWeight(1).fontSize(9).fontColor('#88958E');
        Text('').width(20);
      }
      Scroll() {
        Column() {
          ForEach(this.terms, (term: Term, index: number) => {
            Column({ space: 4 }) {
              Row({ space: 4 }) {
                TextInput({ text: term.source, placeholder: '原文术语' }).fontSize(10).fontColor('#2D3A34').layoutWeight(1)
                  .enabled(this.loaded).backgroundColor('#F7F9F7').borderRadius(3).onChange((value: string) => this.updateTerm(index, 'source', value));
                Text('→').fontSize(9).fontColor('#9AA59F');
                TextInput({ text: term.target, placeholder: '标准译法' }).fontSize(10).fontColor('#3D654F').layoutWeight(1)
                  .enabled(this.loaded).backgroundColor('#F7F9F7').borderRadius(3).onChange((value: string) => this.updateTerm(index, 'target', value));
                Text('×').fontSize(13).fontColor('#A16E65').onClick(() => this.removeTerm(index));
              }
              TextInput({ text: term.note, placeholder: '备注（语境、禁用译法等）' }).fontSize(9).height(28).backgroundColor('#F7F9F7').borderRadius(3)
                .enabled(this.loaded).onChange((value: string) => this.updateTerm(index, 'note', value));
            }.width('100%').padding({ bottom: 7 }).border({ color: '#EDF0EE', width: { bottom: 1 } });
          }, (_term: Term, index: number) => `${index}`);
          if (this.terms.length === 0) {
            Text('添加术语后，编辑器会标出需核对的段落。').fontSize(10).fontColor('#839089').padding({ top: 10, bottom: 10 });
          }
        }
      }.layoutWeight(1).scrollBar(BarState.Auto);
    }.width('100%').layoutWeight(1).padding(13).backgroundColor(Color.White).border({ color: '#E4EAE6', width: 1 }).borderRadius(5).alignItems(HorizontalAlign.Start);
  }
}


