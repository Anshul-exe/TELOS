import React from "react";
import Tasks from "../Tasks";
import { Paper, TextField, Checkbox, Button } from "@material-ui/core";
import {
  addTask,
  getTasks,
  updateTask,
  deleteTask,
} from "../services/taskServices";
import "./TaskView.css";

class TaskView extends Tasks {
  state = { tasks: [], currentTask: "", error: null };

  // Override componentDidMount to add user-facing error handling
  async componentDidMount() {
    try {
      const { data } = await getTasks();
      this.setState({ tasks: data });
    } catch (error) {
      this.setState({ error: "Failed to load tasks. Please refresh the page." });
    }
  }

  // Override handleSubmit to surface errors to the user
  handleSubmit = async (e) => {
    e.preventDefault();
    this.setState({ error: null });
    const originalTasks = this.state.tasks;
    try {
      const { data } = await addTask({ task: this.state.currentTask });
      const tasks = [...originalTasks, data];
      this.setState({ tasks, currentTask: "" });
    } catch (error) {
      this.setState({ error: "Failed to add task. Please try again." });
    }
  };

  // Override handleUpdate to surface errors to the user
  handleUpdate = async (currentTask) => {
    this.setState({ error: null });
    const originalTasks = this.state.tasks;
    try {
      const tasks = [...originalTasks];
      const index = tasks.findIndex((task) => task._id === currentTask);
      tasks[index] = { ...tasks[index] };
      tasks[index].completed = !tasks[index].completed;
      this.setState({ tasks });
      await updateTask(currentTask, {
        completed: tasks[index].completed,
      });
    } catch (error) {
      this.setState({ tasks: originalTasks, error: "Failed to update task." });
    }
  };

  // Override handleDelete to surface errors to the user
  handleDelete = async (currentTask) => {
    this.setState({ error: null });
    const originalTasks = this.state.tasks;
    try {
      const tasks = originalTasks.filter((task) => task._id !== currentTask);
      this.setState({ tasks });
      await deleteTask(currentTask);
    } catch (error) {
      this.setState({
        tasks: originalTasks,
        error: "Failed to delete task.",
      });
    }
  };

  render() {
    const { tasks, currentTask, error } = this.state;
    return (
      <Paper elevation={3} className="todo-container">
        <h2 className="todo-title">My Tasks</h2>
        {error && (
          <div className="task-error">
            <span>{error}</span>
            <button
              className="task-error-dismiss"
              onClick={() => this.setState({ error: null })}
              aria-label="Dismiss error"
            >
              &#x2715;
            </button>
          </div>
        )}
        <form onSubmit={this.handleSubmit} className="task-form">
          <TextField
            id="new-task-input"
            variant="outlined"
            size="small"
            className="task-input"
            value={currentTask}
            required={true}
            onChange={this.handleChange}
            placeholder="Add new task"
          />
          <Button
            id="add-task-btn"
            className="add-task-btn"
            color="primary"
            variant="outlined"
            type="submit"
          >
            Add
          </Button>
        </form>
        <div className="tasks-list">
          {tasks.length === 0 && !error && (
            <p className="tasks-empty">No tasks yet. Add one above!</p>
          )}
          {tasks.map((task) => (
            <Paper key={task._id} className="task-item">
              <Checkbox
                checked={task.completed}
                onClick={() => this.handleUpdate(task._id)}
                color="primary"
              />
              <div
                className={
                  task.completed ? "task-text completed" : "task-text"
                }
              >
                {task.task}
              </div>
              <Button
                onClick={() => this.handleDelete(task._id)}
                color="secondary"
                className="delete-task-btn"
              >
                Delete
              </Button>
            </Paper>
          ))}
        </div>
      </Paper>
    );
  }
}

export default TaskView;
