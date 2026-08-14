import Foundation
import CreativeWorkshopCore

/// R5 瘦身·任务 24（PRD 24.11 / P2-9）：素材（想法）与选题的增删改查、以及两条生成选题的
/// 动作，从 `WorkshopStore` 搬到这里。
///
/// `currentTopicPayload` / `topicPayload` 留在主文件：「快速成稿」「大纲成稿」也要用它们，
/// 而 private 是文件级作用域。搬家不该以放宽可见性为代价。
extension WorkshopStore {
    func newMaterial() {
        selectedIdeaID = nil
        materialTitle = ""
        materialContent = ""
        materialType = "灵感"
        materialTagsText = ""
        statusText = "已新建素材"
    }

    func editIdea(_ idea: Idea) {
        selectedIdeaID = idea.id
        materialTitle = idea.title ?? ""
        materialContent = idea.content
        materialType = idea.type ?? "灵感"
        materialTagsText = tagsText(idea.tags)
    }

    func saveIdea() async {
        guard canSaveMaterial else {
            statusText = "请先填写素材内容"
            return
        }

        await run("保存素材") {
            let idea = try self.database.saveIdea(
                id: self.selectedIdeaID,
                payload: IdeaSaveRequest(
                    title: self.materialTitle,
                    content: self.materialContent,
                    type: self.materialType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "灵感" : self.materialType,
                    tags: self.tagsFromText(self.materialTagsText),
                    used: self.selectedIdea?.used ?? 0,
                    related_article_id: self.selectedIdea?.related_article_id
                )
            )
            self.selectedIdeaID = idea.id
            self.ideas = try self.database.listIdeas()
            self.stats = try self.database.overviewStats()
            self.statusText = "素材已保存"
        }
    }

    func deleteSelectedIdea() async {
        guard let selectedIdeaID else {
            statusText = "请先选择素材"
            return
        }

        await run("删除素材") {
            try self.database.deleteIdea(id: selectedIdeaID)
            self.newMaterial()
            self.ideas = try self.database.listIdeas()
            self.stats = try self.database.overviewStats()
            self.statusText = "素材已删除"
        }
    }

    func useIdeaInSession(_ idea: Idea) {
        let block = """
        【\(idea.type ?? "素材")】\(idea.displayTitle)
        \(idea.content)
        """
        materials = [materials.trimmingCharacters(in: .whitespacesAndNewlines), block]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        if ideaInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ideaInput = idea.title ?? String(idea.content.prefix(40))
        }
        do {
            _ = try database.markIdeaUsed(id: idea.id, used: true)
            ideas = try database.listIdeas()
            stats = try database.overviewStats()
            statusText = "素材已加入当前写作"
        } catch {
            statusText = error.localizedDescription
        }
    }

    func generateTopicsFromIdea(_ idea: Idea) async {
        await run("从素材生成选题", cancellable: true) {
            let seed = idea.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let input = seed?.isEmpty == false ? seed! : String(idea.content.prefix(60))
            var analysis = try self.analysisRequest(template: .topics)
            analysis.context.idea = input
            analysis.context.direction = self.normalizedDirection
            analysis.context.materials_excerpt = idea.content
            analysis.context.material_count = 1

            let outcome = try await self.writingWorkflow.generateTopics(
                WritingWorkflow.TopicsRequest(
                    analysis: analysis,
                    actionTitle: "从素材生成选题",
                    existingTopics: self.topics,
                    markIdeaUsedID: idea.id
                )
            )
            self.projectAgentRun(outcome.agentRun)

            self.ideas = try self.database.listIdeas()
            self.projectGeneratedTopics(outcome)
        }
    }

    func useTopic(_ topic: Topic) {
        selectedTopicID = topic.id
        title = topic.title
        summary = topic.description ?? ""
        writingDirection = topic.direction ?? writingDirection
        if ideaInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ideaInput = topic.description ?? topic.core_viewpoint ?? topic.title
        }
        if outline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            outline = defaultOutline(for: topic)
        }
    }

    func deleteTopic(_ topic: Topic) async {
        await run("删除选题") {
            try self.database.deleteTopic(id: topic.id)
            if self.selectedTopicID == topic.id {
                self.selectedTopicID = nil
            }
            self.topics = try self.database.listTopics()
            self.stats = try self.database.overviewStats()
            self.statusText = "选题「\(topic.title)」已删除"
        }
    }

    /// 两条选题路径共用的投影：入库结果、被过滤的重复、选用第一条、刷新统计与状态。
    private func projectGeneratedTopics(_ outcome: WritingWorkflow.TopicsOutcome) {
        topics = (try? database.listTopics()) ?? topics
        lastFilteredDuplicateTopics = outcome.duplicates
        if let firstTopic = outcome.created.first {
            useTopic(firstTopic)
        }
        stats = try? database.overviewStats()
        statusText = topicsGeneratedStatusText(
            created: outcome.created.count,
            duplicates: outcome.duplicates.count
        )
    }

    func generateTopics() async {
        guard !ideaInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusText = "请先输入想法"
            return
        }

        await run("生成选题", cancellable: true) {
            var analysis = try self.analysisRequest(template: .topics)
            analysis.context.idea = self.ideaInput
            analysis.context.direction = self.normalizedDirection
            analysis.context.materials_excerpt = self.materials

            let outcome = try await self.writingWorkflow.generateTopics(
                WritingWorkflow.TopicsRequest(
                    analysis: analysis,
                    actionTitle: "生成选题",
                    existingTopics: self.topics
                )
            )
            self.projectAgentRun(outcome.agentRun)
            self.projectGeneratedTopics(outcome)
        }
    }

    private func topicsGeneratedStatusText(created: Int, duplicates: Int) -> String {
        if created == 0 && duplicates > 0 {
            return "生成的选题都与已有选题重复，已自动过滤"
        }
        if created == 0 {
            return "没有生成新选题"
        }
        if duplicates > 0 {
            return "已生成 \(created) 个选题（另有 \(duplicates) 个与已有选题重复，已过滤）"
        }
        return "已生成 \(created) 个选题"
    }

    private func tagsFromText(_ text: String) -> [String] {
        text
            .split { character in
                character == "," || character == "，" || character == "、" || character == " "
            }
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func tagsText(_ values: [String]) -> String {
        values.joined(separator: "，")
    }

    /// 选中选题却还没有大纲时，先给一个按选题字段填好的骨架，作者在它上面改。
    private func defaultOutline(for topic: Topic) -> String {
        """
        # \(topic.title)

        ## 开头
        从一个具体场景切入，让读者知道这篇文章为什么和自己有关。

        ## 核心观察
        \(topic.core_viewpoint ?? topic.description ?? "把核心观点讲清楚。")

        ## 展开
        结合经历、素材或案例，说明这个判断为什么成立。

        ## 结尾
        回到个人感受或现实选择，留下有回味的收束。
        """
    }
}
