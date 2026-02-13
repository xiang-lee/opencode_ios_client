//
//  TodoListInlineView.swift
//  OpenCodeClient
//

import SwiftUI

struct TodoListInlineView: View {
    let todos: [TodoItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(todos) { todo in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(todo.isCompleted ? .green : .secondary)
                        .font(.caption)
                        .padding(.top, 1)
                    Text(todo.content)
                        .font(.caption2)
                        .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                        .strikethrough(todo.isCompleted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.top, 4)
    }
}
